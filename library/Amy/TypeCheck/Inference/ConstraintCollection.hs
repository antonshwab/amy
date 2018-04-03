{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TupleSections #-}

-- | Collect constraints from the AST

module Amy.TypeCheck.Inference.ConstraintCollection
  ( Inference
  , runInference
  , TypeError(..)
  , freshTypeVariable
  , letters
  , inferExpr
  , Constraint(..)
    -- TODO: Do we need to export these?
  , Assumptions
  , assumptionKeys
  ) where

import Control.Monad.Except
import Control.Monad.Reader
import Control.Monad.State.Strict
import Data.Foldable (foldl')
import qualified Data.List.NonEmpty as NE
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text, pack)

import Amy.Literal
import Amy.Names
import Amy.Prim
import Amy.Renamer.AST
import Amy.Syntax.Located
import Amy.Type

--
-- Inference Monad
--

-- | Holds a set of monomorphic variables in a 'ReaderT' and a 'State' 'Int'
-- counter for producing type variables.
newtype Inference a = Inference (ReaderT (Set TVar) (StateT Int (Except TypeError)) a)
  deriving (Functor, Applicative, Monad, MonadReader (Set TVar), MonadState Int, MonadError TypeError)

runInference :: Inference a -> Either TypeError a
runInference (Inference action) = runExcept $ evalStateT (runReaderT action Set.empty) 0

-- TODO: Separate monads for constraint collection and unification.

-- TODO: Don't use Except, use Validation

-- TODO: Move these into the main Error type
-- TODO: Include source spans in these errors
data TypeError
  = UnificationFail !(Type PrimitiveType) !(Type PrimitiveType)
  | InfiniteType TVar !(Type PrimitiveType)
  | UnboundVariable ValueName
  | Ambigious [Constraint]
  | UnificationMismatch [Type PrimitiveType] [Type PrimitiveType]
  deriving (Show, Eq)

-- | Generate a fresh type variable
freshTypeVariable :: Inference TVar
freshTypeVariable = do
  modify' (+ 1)
  TVar . (letters !!) <$> get

-- TODO: Don't use letters for type variables, just use integers. Then at the
-- end of inference we can turn all the type variables into letters so the user
-- gets nice letters to see.
letters :: [Text]
letters = [1..] >>= fmap pack . flip replicateM ['a'..'z']

-- | Add a monomorphic variable to the monomorphic set and run a computation
extendMonomorphicSet :: [TVar] -> Inference a -> Inference a
extendMonomorphicSet xs = local (Set.union (Set.fromList xs))

--
-- Inference Functions
--

inferBinding :: RBinding -> Inference (Assumptions, [Constraint], Type PrimitiveType)
inferBinding (RBinding _ _ args body) = do
  -- Instantiate a fresh type variable for every argument
  argsAndTyVars <- traverse (\arg -> (arg,) <$> freshTypeVariable) args

  -- Infer the type of the expression after extending the monomorphic set with
  -- the type variables for the arguments.
  let
    tyVars = snd <$> argsAndTyVars
  (asBody, consBody, tyBody) <- extendMonomorphicSet tyVars $ inferExpr body

  -- Create equality constraints for each argument by looking up the argument
  -- in the assumptions from the body.
  let
    argConstraint (Located _ argName, argTyVar) =
      (\t -> EqConstraint t (TyVar argTyVar)) <$> lookupAssumption argName asBody
    argConstraints = concatMap argConstraint argsAndTyVars
  pure
    ( foldl' removeAssumption asBody (locatedValue <$> args)
    , consBody ++ argConstraints
    , typeFromNonEmpty (NE.fromList $ (TyVar <$> tyVars) ++ [tyBody])
    )

-- | Collect constraints for an expression.
inferExpr :: RExpr -> Inference (Assumptions, [Constraint], Type PrimitiveType)
inferExpr (RELit (Located _ (LiteralInt _))) = pure (emptyAssumptions, [], TyCon IntType)
inferExpr (RELit (Located _ (LiteralDouble _))) = pure (emptyAssumptions, [], TyCon DoubleType)
inferExpr (RELit (Located _ (LiteralBool _))) = pure (emptyAssumptions, [], TyCon BoolType)
inferExpr (REVar (Located _ name)) = do
  -- For a Var, generate a fresh type variable and add it to the assumption set
  tyVar <- TyVar <$> freshTypeVariable
  pure (singletonAssumption name tyVar, [], tyVar)
inferExpr (REIf (RIf pred' then' else')) = do
  -- If statements are simple. Merge all the assumptions/constraints from each
  -- sub expression. Then add a constraint saying the predicate must be a Bool,
  -- and that the then and else branches have equal types.
  (asPred, consPred, tyPred) <- inferExpr pred'
  (asThen, consThen, tyThen) <- inferExpr then'
  (asElse, consElse, tyElse) <- inferExpr else'
  pure
    ( asPred `mergeAssumptions` asThen `mergeAssumptions` asElse
    , consPred ++ consThen ++ consElse ++ [EqConstraint tyPred (TyCon BoolType), EqConstraint tyThen tyElse]
    , tyThen
    )
inferExpr (RELet (RLet bindings expression)) = do
  bindingsInference <- traverse inferBinding bindings
  (asExpression, consExpression, tyExpression) <- inferExpr expression
  monomorphicSet <- ask
  let
    bindingNames = locatedValue . rBindingName <$> bindings
    bindingAssumptions = (\(as, _, _) -> as) <$> bindingsInference
    bindingConstraints = (\(_, cs, _) -> cs) <$> bindingsInference
    bindingTypes = (\(_, _, t) -> t) <$> bindingsInference

    bindingConstraint (bindingName, bindingType) =
      (\t -> ImplicitInstanceConstraint t monomorphicSet bindingType)
      <$> lookupAssumption bindingName asExpression
    newConstraints = concatMap bindingConstraint (zip bindingNames bindingTypes)

    -- Remove binding names from expression assumption
    expressionAssumption = foldl' removeAssumption asExpression bindingNames
  pure
    ( concatAssumptions bindingAssumptions `mergeAssumptions` expressionAssumption
    , concat bindingConstraints ++ consExpression ++ newConstraints
    , tyExpression
    )
inferExpr (REApp (RApp func args)) = do
  -- For an App, we first collect constraints for the function and the
  -- arguments. Then, we instantiate a fresh type variable. The assumption sets
  -- and constraint sets are merged, and the additional constraint that the
  -- function is a TyApp from the args to the fresh type variable is added.
  (asFunc, consFunc, tyFunc) <- inferExpr func
  argsInference <- NE.toList <$> traverse inferExpr args
  let
    argAssumptions = (\(as, _, _) -> as) <$> argsInference
    argConstraints = (\(_, cs, _) -> cs) <$> argsInference
    argTypes = (\(_, _, t) -> t) <$> argsInference
  tyVar <- TyVar <$> freshTypeVariable
  let
    newConstraint = EqConstraint tyFunc (typeFromNonEmpty $ NE.fromList (argTypes ++ [tyVar]))
  pure
    ( concatAssumptions argAssumptions `mergeAssumptions` asFunc
    , consFunc ++ concat argConstraints ++ [newConstraint]
    , tyVar
    )

--
-- Constraints
--

-- | A 'Constraint' places a restriction on what type is assigned to a
-- variable. Constraints are collected and then solved after collection.
data Constraint
  = EqConstraint !(Type PrimitiveType) !(Type PrimitiveType)
    -- ^ Indicates types should be unified
  | ExplicitInstanceConstraint !(Type PrimitiveType) !(Scheme PrimitiveType)
  | ImplicitInstanceConstraint !(Type PrimitiveType) !(Set TVar) !(Type PrimitiveType)
  deriving (Show, Eq)

--
-- Assumptions
--

-- | An Assumption is an assignment of a type variable to a free variable in an
-- expression. An Assumption is created during the inference of a Var in an
-- expression, and assumptions are bubbled up the AST during bottom-up
-- constraint collection. There can be more than on assumption for a given
-- variable.
newtype Assumptions = Assumptions { unAssumptions :: [(ValueName, Type PrimitiveType)] }
  deriving (Show, Eq)

emptyAssumptions :: Assumptions
emptyAssumptions = Assumptions []

-- | Remove an assumption from the assumption set. This is done when we
-- encounter a binding for a variable, like a lambda or let expression
-- variable. The assumption gets "converted" into a constraint.
removeAssumption :: Assumptions -> ValueName -> Assumptions
removeAssumption (Assumptions xs) name = Assumptions (filter (\(n, _) -> n /= name) xs)

lookupAssumption :: ValueName -> Assumptions -> [Type PrimitiveType]
lookupAssumption name (Assumptions xs) = map snd (filter (\(n, _) -> n == name) xs)

concatAssumptions :: [Assumptions] -> Assumptions
concatAssumptions = foldl' mergeAssumptions emptyAssumptions

mergeAssumptions :: Assumptions -> Assumptions -> Assumptions
mergeAssumptions (Assumptions a) (Assumptions b) = Assumptions (a ++ b)

singletonAssumption :: ValueName -> Type PrimitiveType -> Assumptions
singletonAssumption x y = Assumptions [(x, y)]

assumptionKeys :: Assumptions -> [ValueName]
assumptionKeys (Assumptions xs) = map fst xs
