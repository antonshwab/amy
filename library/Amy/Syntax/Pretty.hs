module Amy.Syntax.Pretty
  ( prettyModule
  , prettyDeclaration
  , prettyTypeDeclaration
  , prettyExpr
  ) where

import Data.Foldable (toList)

import Amy.Literal
import Amy.Pretty
import Amy.Syntax.AST

mkPrettyType :: Type -> PrettyType ann
mkPrettyType (TyCon (Located _ var)) = PTyDoc $ pretty var
mkPrettyType (TyVar (Located _ var)) = PTyDoc $ pretty var
mkPrettyType (TyFun ty1 ty2) = PTyFun (mkPrettyType ty1) (mkPrettyType ty2)

mkPrettyScheme :: Scheme -> PrettyScheme ann
mkPrettyScheme (Forall vars ty) = PForall (pretty . locatedValue <$> vars) (mkPrettyType ty)

prettyModule :: Module -> Doc ann
prettyModule (Module decls) = vcatTwoHardLines (prettyDeclaration <$> decls)

prettyDeclaration :: Declaration -> Doc ann
prettyDeclaration (DeclBinding binding) = prettyBinding' binding
prettyDeclaration (DeclBindingType bindingTy) = prettyBindingType' bindingTy
prettyDeclaration (DeclExtern (Extern (Located _ name) ty)) =
  prettyExtern (pretty name) (mkPrettyType ty)
prettyDeclaration (DeclType (TypeDeclaration (Located _ tyName) cons)) =
  prettyTypeDeclaration (pretty tyName) (prettyConstructor <$> cons)
 where
  prettyConstructor (DataConstructor (Located _ conName) mArg) =
    prettyDataConstructor (pretty conName) (pretty . locatedValue <$> mArg)

prettyBinding' :: Binding -> Doc ann
prettyBinding' (Binding (Located _ name) args body) =
  prettyBinding (pretty name) (pretty . locatedValue <$> args) (prettyExpr body)

prettyBindingType' :: BindingType -> Doc ann
prettyBindingType' (BindingType (Located _ name) ty) =
  prettyBindingScheme (pretty name) (mkPrettyScheme ty)

prettyExpr :: Expr -> Doc ann
prettyExpr (ELit (Located _ lit)) = pretty $ showLiteral lit
prettyExpr (EVar var) = prettyVar var
prettyExpr (EIf (If pred' then' else')) =
  prettyIf (prettyExpr pred') (prettyExpr then') (prettyExpr else')
prettyExpr (ECase (Case scrutinee matches)) =
  prettyCase (prettyExpr scrutinee) (toList $ mkMatch <$> matches)
 where
  mkMatch (Match pat body) = (prettyPattern pat, prettyExpr body)
prettyExpr (ELet (Let bindings body)) =
  prettyLet (prettyLetBinding <$> bindings) (prettyExpr body)
 where
  prettyLetBinding (LetBinding binding) = prettyBinding' binding
  prettyLetBinding (LetBindingType bindingTy) = prettyBindingType' bindingTy
prettyExpr (EApp (App f args)) = sep $ prettyExpr f : (prettyExpr <$> toList args)
prettyExpr (EParens expr) = parens $ prettyExpr expr

prettyVar :: Var -> Doc ann
prettyVar (VVal (Located _ var)) = pretty var
prettyVar (VCons (Located _ var)) = pretty var

prettyPattern :: Pattern -> Doc ann
prettyPattern (PLit (Located _ lit)) = pretty $ showLiteral lit
prettyPattern (PVar (Located _ var)) = pretty var
prettyPattern (PParens pat) = parens (prettyPattern pat)
prettyPattern (PCons (PatCons (Located _ var) mArg)) =
  pretty var <> maybe mempty prettyArg mArg
 where
  prettyArg = (space <>) . prettyArg'
  prettyArg' arg@PCons{} = parens (prettyPattern arg)
  prettyArg' arg = prettyPattern arg
