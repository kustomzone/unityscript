
namespace UnityScript.Tests

import NUnit.Framework
	
[TestFixture]
class ExpandoTestFixture(AbstractIntegrationTestFixture):
	
	override def SetCompilationOptions():
		super()
		Parameters.Expando = true

	
	[Test] def expando_1():
		RunTestCase("tests/expando/expando-1.js")
		
	
	[Test] def expando_2():
		RunTestCase("tests/expando/expando-2.js")
		
	[Category("FailsOnMono")]
	[Test] def expando_gc_3():
		RunTestCase("tests/expando/expando-gc-3.js")
		