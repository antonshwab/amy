module Amy.Codegen.TypeConstructors
  ( TypeCompilationMethod(..)
  , typeCompilationMethod
  , findCompilationMethod
  ) where

import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isNothing)

import Amy.ANF.AST as ANF
import Amy.Prim

data TypeCompilationMethod
  = CompileUnboxed !PrimitiveType
    -- ^ Unbox to the given type
  | CompileEnum !Int
    -- ^ Compile as an integer enum
  | CompileTaggedPairs !Int
    -- ^ Compile as a pair of integer tag and pointer to data
  deriving (Show, Eq)

-- | Decide how we are going to compile a type declaration.
typeCompilationMethod
  :: ANF.TypeDeclaration
  -> (Map ANF.ConstructorName TypeCompilationMethod, (TyConInfo, Maybe PrimitiveType))
typeCompilationMethod (ANF.TypeDeclaration tyName constructors) =
  case constructors of
    -- Single constructor around another type
    ANF.DataConstructor conName (Just argTy) :| _ ->
      let argTy' = assertPrimitiveType argTy
      in (Map.singleton conName $ CompileUnboxed argTy', (tyName, Just argTy'))

    _ ->
      -- Check if we can do an enum. This is when all constructors have no
      -- arguments.
      if all (isNothing . dataConstructorArgument) constructors
      then
        let
          mkMethod (ANF.DataConstructor conName _, i) = (conName, CompileEnum i)
        in
          ( Map.fromList $ mkMethod <$> zip (NE.toList constructors) [0..]
          , (tyName, Just IntType)
          )
      -- Can't do an enum. We'll have to use tagged pairs.
      else
        let
          mkMethod (ANF.DataConstructor conName _, i) = (conName, CompileTaggedPairs i)
        in
          ( Map.fromList $ mkMethod <$> zip (NE.toList constructors) [0..]
          , (tyName, Nothing)
          )

findCompilationMethod
  :: ConstructorName
  -> Map ConstructorName TypeCompilationMethod
  -> TypeCompilationMethod
findCompilationMethod consName compilationMethods =
  fromMaybe (error $ "No compilation method for " ++ show consName) $ Map.lookup consName compilationMethods

assertPrimitiveType :: TyConInfo -> PrimitiveType
assertPrimitiveType info@(ANF.TyConInfo _ _ mPrim) =
  fromMaybe (error $ "Cannot unbox, not a primitive type! " ++ show info) mPrim
