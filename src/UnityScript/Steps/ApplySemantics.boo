namespace UnityScript.Steps

import UnityScript.Core

import Boo.Lang.Compiler.Ast
import Boo.Lang.Compiler.Steps
import System.Linq

class ApplySemantics(AbstractVisitorCompilerStep):
	
	override def Run():
		Visit(CompileUnit)
	
	class DeclareGlobalVariables(DepthFirstTransformer):
		
		_class as ClassDefinition
		
		def constructor(cd as ClassDefinition):
			_class = cd
			
		override def EnterBlock(node as Block):
			if node.ParentNode isa Method: return true
			return false
		
		override def OnDeclarationStatement(node as DeclarationStatement):
			
			return if node.ContainsAnnotation('PrivateScope')
		
			field = [|
				public $(node.Declaration.Name) as $(node.Declaration.Type) = $(node.Initializer)
			|]			
			field.LexicalInfo = node.LexicalInfo
			_class.Members.Add(field)
			
			RemoveCurrentNode()
			
	UnityScriptParameters as UnityScript.UnityScriptCompilerParameters:
		get: return _context.Parameters
	
	override def OnModule(module as Module):
		
		SetUpDefaultImports(module)
		if ModuleContainsOnlyTypeDefinitions(module):
			return

		script = FindOrCreateScriptClass(module)
		MakeItPartial(script)
		MoveMembers(module, script)
		SetUpMainMethod(module, script)
		MoveAttributes(module, script)
		module.Members.Add(script)
		SetScriptClass(Context, script)
		
	def ModuleContainsOnlyTypeDefinitions(module as Module):
		return not module.Members.IsEmpty and module.Members.All({ m | m isa TypeDefinition }) and module.Globals.IsEmpty and module.Attributes.IsEmpty
		
	def SetUpMainMethod(module as Module, script as TypeDefinition):		
		TransformGlobalVariablesIntoFields(module, script)
		MoveGlobalStatementsToMainMethodOf(script, module)
		
	def MoveGlobalStatementsToMainMethodOf(script as TypeDefinition, module as Module):
		
		main = ExistingMainMethodOn(script)
		
		if main is null:
			main = NewMainMethodFor(module)
			script.Members.Add(main)
		else:
			Warnings.Add(UnityScriptWarnings.ScriptMainMethodIsImplicitlyDefined(main.LexicalInfo, main.Name))
			
		main.Body.Statements.AddRange(module.Globals.Statements)
		module.Globals.Statements.Clear()
		
	def TransformGlobalVariablesIntoFields(module as Module, script as TypeDefinition):
		if not UnityScriptParameters.GlobalVariablesBecomeFields:
			return
		module.Globals.Accept(DeclareGlobalVariables(script))
		
	def ExistingMainMethodOn(typeDef as TypeDefinition):
		return typeDef.Members.OfType[of Method]().FirstOrDefault(IsMainMethod)
		
	def IsMainMethod(m as Method):
		return (
			m is not null
			and m.Name == ScriptMainMethod
			and len(m.Parameters) == 0)
		
	def MakeItPartial(global as ClassDefinition):
		global.Modifiers |= TypeMemberModifiers.Partial
		
	def SetUpDefaultImports(module as Module):
		for ns as string in self.UnityScriptParameters.Imports:
			module.Imports.Add(Import(ns))
					
	def MoveAttributes(fromType as TypeDefinition, toType as TypeDefinition):
		toType.Attributes.AddRange(fromType.Attributes)
		fromType.Attributes.Clear()
		
	def MoveMembers(fromType as TypeDefinition, toType as TypeDefinition):
		moved = []
		for member in fromType.Members:
			if not member isa TypeDefinition:
				movedMember = MovedMember(toType, member)
				toType.Members.Add(movedMember)
				Visit(movedMember)
				moved.Add(member)
			else:
				Visit(member)
		
		for member in moved:
			fromType.Members.Remove(member)
			
	def MovedMember(toType as TypeDefinition, member as TypeMember):
		if not toType.ContainsAnnotation("UserDefined"): return member
		if not IsConstructorMethod(toType, member): return member
		return ConstructorFromMethod(member)
		
	def IsConstructorMethod(toType as TypeDefinition, member as TypeMember):
		if member.NodeType != NodeType.Method: return false
		return toType.Name == member.Name
		
	def ConstructorFromMethod(method as Method):
		return Constructor(
			Parameters: method.Parameters,
			Body: method.Body, 
			Attributes: method.Attributes,
			Modifiers: method.Modifiers,
			LexicalInfo: method.LexicalInfo,
			EndSourceLocation: method.EndSourceLocation)
		
	def FindOrCreateScriptClass(module as Module):
		for existing in module.Members.OfType of ClassDefinition():
			if existing.Name == module.Name:
				module.Members.Remove(existing)
				if existing.IsPartial: AddScriptBaseType(existing)
				existing.Annotate("UserDefined")
				return existing
						
		klass = ClassDefinition(module.LexicalInfo, Name: module.Name, EndSourceLocation: module.EndSourceLocation, IsSynthetic: true)
		AddScriptBaseType(klass)
		return klass
		
	def AddScriptBaseType(klass as ClassDefinition):
		klass.BaseTypes.Add(CodeBuilder.CreateTypeReference(UnityScriptParameters.ScriptBaseType))
		
	ScriptMainMethod:
		get: return self.UnityScriptParameters.ScriptMainMethod
	
	def NewMainMethodFor(module as Module):
		return Method(
			LexicalInfo: (Copy(module.Globals.Statements[0].LexicalInfo) if not module.Globals.IsEmpty else module.LexicalInfo),
			Name: ScriptMainMethod,
			Modifiers: TypeMemberModifiers.Public | TypeMemberModifiers.Virtual,
			EndSourceLocation: module.EndSourceLocation)
		
def Copy(li as LexicalInfo):
	return LexicalInfo(li.FileName, li.Line, li.Column)

