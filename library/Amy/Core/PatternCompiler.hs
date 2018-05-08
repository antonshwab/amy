{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

-- | Pattern match compiler, inspired by the great book Implementation of
-- Functional Programming Languages.

module Amy.Core.PatternCompiler
  ( match
  , VarSubst(..)
  , Pattern(..)
  , Con(..)
  , Equation
  , CaseExpr(..)
  , Clause(..)
  ) where

import Control.Monad.Reader
import Control.Monad.State.Strict
import Data.List (sortOn)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Text (Text, pack)

import Amy.Literal

data Pattern
  = PCon !Con ![Pattern]
  | PVar !Variable
  deriving (Show, Eq)

type Variable = Text

data Con
  = Con !Text !Arity !Span
  | ConLit !Literal
  deriving (Show, Eq, Ord)

conArity :: Con -> Arity
conArity (Con _ arity _) = arity
conArity (ConLit _) = 0

conSpan :: Con -> Maybe Span
conSpan (Con _ _ span') = Just span'
conSpan (ConLit _) = Nothing

type Arity = Int
type Span = Int

type Equation expr = ([Pattern], expr)

data CaseExpr expr
  = Case !Variable ![Clause expr] !(Maybe (CaseExpr expr))
  | Expr !expr
  | Fail
  | Error
  deriving (Show, Eq)

data Clause expr = Clause !Con ![Variable] !(CaseExpr expr)
  deriving (Show, Eq)

-- TODO: Handle substitutions when matching variables

newtype Match expr a = Match (ReaderT (VarSubst expr) (State Int) a)
  deriving (Functor, Applicative, Monad, MonadReader (VarSubst expr), MonadState Int)

newtype VarSubst expr = VarSubst { _unVarSubst :: expr -> Variable -> Variable -> expr }

substituteVariable :: expr -> Variable -> Variable -> Match expr expr
substituteVariable expr var newVar = do
  VarSubst f <- ask
  pure $ f expr var newVar

runMatch :: VarSubst expr -> Int -> Match expr a -> a
runMatch subst i (Match action) = evalState (runReaderT action subst) i

freshVar :: Match expr Variable
freshVar = do
  modify' (+ 1)
  id' <- get
  pure $ "_u" <> pack (show id')

match :: (Show expr) => VarSubst expr -> [Variable] -> [Equation expr] -> CaseExpr expr
match subst vars eqs = runMatch subst 0 $ match' vars eqs Error

match' :: (Show expr) => [Variable] -> [Equation expr] -> CaseExpr expr -> Match expr (CaseExpr expr)
match' [] eqs def = pure $ foldr applyFatbar def (Expr . snd <$> eqs)
match' vars eqs def = foldrM (matchGroup vars) def $ groupEquations eqs

-- TODO: Refactor the algorithm so we can use foldM instead of foldrM
foldrM :: Monad m => (a -> b -> m b) -> b -> [a] -> m b
foldrM _ d [] = return d
foldrM f d (x:xs) = f x =<< foldrM f d xs

applyFatbar :: (Show expr) => CaseExpr expr -> CaseExpr expr -> CaseExpr expr
applyFatbar e Fail = e
applyFatbar Fail e = e
applyFatbar e@Case{} _ = error $ "Can't guarantee case doesn't fail yet " ++ show e
applyFatbar e@(Expr _) _ = e
applyFatbar Error _ = Error

--
-- Equation grouping
--

data GroupedEquations expr
  = EmptyEquations ![expr]
  | VarEquations ![VarEquation expr]
  | ConEquations ![ConEquation expr]
  deriving (Show, Eq)

data VarEquation expr = VarEquation !Variable !(Equation expr)
  deriving (Show, Eq)

data ConEquation expr = ConEquation !Con ![Pattern] !(Equation expr)
  deriving (Show, Eq)

conEquationCon :: ConEquation expr -> Con
conEquationCon (ConEquation con _ _) = con

groupEquations :: [Equation expr] -> [GroupedEquations expr]
groupEquations = concatGroupedEquations . fmap equationType

equationType :: Equation expr -> GroupedEquations expr
equationType ([], expr) = EmptyEquations [expr]
equationType (PVar var:ps, expr) = VarEquations [VarEquation var (ps, expr)]
equationType (PCon con ps:ps', expr) = ConEquations [ConEquation con ps' (ps, expr)]

concatGroupedEquations :: [GroupedEquations expr] -> [GroupedEquations expr]
concatGroupedEquations [] = []
concatGroupedEquations [x] = [x]
concatGroupedEquations (x:y:xs) =
  case (x, y) of
    (EmptyEquations es1, EmptyEquations es2) -> concatGroupedEquations $ EmptyEquations (es1 ++ es2) : xs
    (VarEquations es1, VarEquations es2) -> concatGroupedEquations $ VarEquations (es1 ++ es2) : xs
    (ConEquations es1, ConEquations es2) -> concatGroupedEquations $ ConEquations (es1 ++ es2) : xs
    (_, _) -> x : concatGroupedEquations (y:xs)

--
-- Matching
--

matchGroup :: (Show expr) => [Variable] -> GroupedEquations expr -> CaseExpr expr -> Match expr (CaseExpr expr)
matchGroup _ (EmptyEquations _) = error "Encountered empty equations in matchGroup"
matchGroup vars (VarEquations eqs) = matchVar vars eqs
matchGroup vars (ConEquations eqs) = matchCon vars eqs

matchVar :: (Show expr) => [Variable] -> [VarEquation expr] -> CaseExpr expr -> Match expr (CaseExpr expr)
matchVar [] _ _ = error "matchVars called with empty variables"
matchVar (u:us) eqs def = do
  let mkNewEquation (VarEquation var (ps, eq)) = (ps,) <$>  substituteVariable eq var u
  eqs' <- traverse mkNewEquation eqs
  match' us eqs' def

matchCon :: (Show expr) => [Variable] -> [ConEquation expr] -> CaseExpr expr -> Match expr (CaseExpr expr)
matchCon [] _ _ = error "matchCon called with empty variables"
matchCon _ [] _ = error "matchCon called with no equations"
matchCon (u:us) eqs@(eq1:_) def = do
  let
    grouped = groupByConstructor eqs
    -- Check for inexhaustive match.
    span' = conSpan . conEquationCon $ eq1
    default' =
      case span' of
        Just s ->
          if length grouped < s
          then Just def
          else Nothing
        Nothing -> Just def
  eqs' <- traverse (matchClause us def) grouped
  pure $ Case u eqs' default'

groupByConstructor :: [ConEquation expr] -> [NonEmpty (ConEquation expr)]
groupByConstructor = fmap (fmap snd) . NE.groupWith fst . sortOn fst . fmap (\eq@(ConEquation con _ _) -> (con, eq))

matchClause :: (Show expr) => [Variable] -> CaseExpr expr -> NonEmpty (ConEquation expr) -> Match expr (Clause expr)
matchClause us def eqs = do
  let con = conEquationCon $ NE.head eqs
  us' <- traverse (const freshVar) [1..conArity con]
  let
    mkNewEquation (ConEquation _ pats' (pats, expr)) = (pats' ++ pats, expr)
  eqs' <- match' (us' ++ us) (NE.toList $ mkNewEquation <$> eqs) def
  pure $ Clause con us' eqs'
