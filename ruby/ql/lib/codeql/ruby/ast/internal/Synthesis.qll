/** Provides predicates for synthesizing AST nodes. */

private import AST
private import TreeSitter
private import codeql.ruby.ast.internal.Call
private import codeql.ruby.ast.internal.Expr
private import codeql.ruby.ast.internal.Variable
private import codeql.ruby.ast.internal.Pattern
private import codeql.ruby.ast.internal.Scope
private import codeql.ruby.AST

/** A synthesized AST node kind. */
newtype SynthKind =
  AddExprKind() or
  AssignExprKind() or
  BitwiseAndExprKind() or
  BitwiseOrExprKind() or
  BitwiseXorExprKind() or
  BraceBlockKind() or
  ClassVariableAccessKind(ClassVariable v) or
  DivExprKind() or
  ExponentExprKind() or
  GlobalVariableAccessKind(GlobalVariable v) or
  InstanceVariableAccessKind(InstanceVariable v) or
  IntegerLiteralKind(int i) { i in [-1000 .. 1000] } or
  LShiftExprKind() or
  LocalVariableAccessRealKind(LocalVariableReal v) or
  LocalVariableAccessSynthKind(TLocalVariableSynth v) or
  LogicalAndExprKind() or
  LogicalOrExprKind() or
  MethodCallKind(string name, boolean setter, int arity) {
    any(Synthesis s).methodCall(name, setter, arity)
  } or
  ModuloExprKind() or
  MulExprKind() or
  RangeLiteralKind(boolean inclusive) { inclusive in [false, true] } or
  RShiftExprKind() or
  SimpleParameterKind() or
  SplatExprKind() or
  StmtSequenceKind() or
  SelfKind(SelfVariable v) or
  SubExprKind() or
  ConstantReadAccessKind(string value) { any(Synthesis s).constantReadAccess(value) }

/**
 * An AST child.
 *
 * Either a new synthesized node or a reference to an existing node.
 */
newtype Child =
  SynthChild(SynthKind k) or
  RealChildRef(TAstNodeReal n) or
  SynthChildRef(TAstNodeSynth n)

/**
 * The purpose of this inlined predicate is to split up child references into
 * those that are from real AST nodes (for which there will be no recursion
 * through `RealChildRef`), and those that are synthesized recursively
 * (for which there will be recursion through `SynthChildRef`).
 *
 * This performs much better than having a combined `ChildRef` that includes
 * both real and synthesized AST nodes, since the recursion happening in
 * `Synthesis::child/3` is non-linear.
 */
pragma[inline]
private Child childRef(TAstNode n) {
  result = RealChildRef(n)
  or
  result = SynthChildRef(n)
}

private newtype TSynthesis = MkSynthesis()

/** A class used for synthesizing AST nodes. */
class Synthesis extends TSynthesis {
  /**
   * Holds if a node should be synthesized as the `i`th child of `parent`, or if
   * a non-synthesized node should be the `i`th child of synthesized node `parent`.
   *
   * `i = -1` is used to represent that the synthesized node is a desugared version
   * of its parent.
   */
  predicate child(AstNode parent, int i, Child child) { none() }

  /**
   * Holds if synthesized node `n` should have location `l`. Synthesized nodes for
   * which this predicate does not hold, inherit their location (recursively) from
   * their parent node.
   */
  predicate location(AstNode n, Location l) { none() }

  /**
   * Holds if a local variable, identified by `i`, should be synthesized for AST
   * node `n`.
   */
  predicate localVariable(AstNode n, int i) { none() }

  /**
   * Holds if a method call to `name` with arity `arity` is needed.
   */
  predicate methodCall(string name, boolean setter, int arity) { none() }

  /**
   * Holds if a constant read access of `name` is needed.
   */
  predicate constantReadAccess(string name) { none() }

  /**
   * Holds if `n` should be excluded from `ControlFlowTree` in the CFG construction.
   */
  predicate excludeFromControlFlowTree(AstNode n) { none() }

  final string toString() { none() }
}

private class Desugared extends AstNode {
  Desugared() { this = any(AstNode sugar).getDesugared() }

  AstNode getADescendant() { result = this.getAChild*() }
}

/**
 * Gets the desugaring level of `n`. That is, the number of desugaring
 * transformations required before the context in which `n` occurs is
 * fully desugared.
 */
int desugarLevel(AstNode n) { result = count(Desugared desugared | n = desugared.getADescendant()) }

/**
 * Use this predicate in `Synthesis::child` to generate an assignment of `value` to
 * synthesized variable `v`, where the assignment is a child of `assignParent` at
 * index `assignIndex`.
 */
bindingset[v, assignParent, assignIndex, value]
private predicate assign(
  AstNode parent, int i, Child child, TLocalVariableSynth v, AstNode assignParent, int assignIndex,
  AstNode value
) {
  parent = assignParent and
  i = assignIndex and
  child = SynthChild(AssignExprKind())
  or
  parent = TAssignExprSynth(assignParent, assignIndex) and
  (
    i = 0 and
    child = SynthChild(LocalVariableAccessSynthKind(v))
    or
    i = 1 and
    child = childRef(value)
  )
}

/** Holds if synthesized node `n` should have location `l`. */
predicate synthLocation(AstNode n, Location l) {
  n.isSynthesized() and any(Synthesis s).location(n, l)
}

private predicate hasLocation(AstNode n, Location l) {
  l = toGenerated(n).getLocation()
  or
  synthLocation(n, l)
}

private module ImplicitSelfSynthesis {
  pragma[nomagic]
  private predicate identifierMethodCallSelfSynthesis(AstNode mc, int i, Child child) {
    child = SynthChild(SelfKind(TSelfVariable(scopeOf(toGenerated(mc)).getEnclosingSelfScope()))) and
    mc = TIdentifierMethodCall(_) and
    i = 0
  }

  private class IdentifierMethodCallSelfSynthesis extends Synthesis {
    final override predicate child(AstNode parent, int i, Child child) {
      identifierMethodCallSelfSynthesis(parent, i, child)
    }
  }

  pragma[nomagic]
  private predicate regularMethodCallSelfSynthesis(TRegularMethodCall mc, int i, Child child) {
    exists(Ruby::AstNode g |
      mc = TRegularMethodCall(g) and
      // If there's no explicit receiver (or scope resolution that acts like a
      // receiver), then the receiver is implicitly `self`.  N.B.  `::Foo()` is
      // not valid Ruby.
      not exists(g.(Ruby::Call).getReceiver()) and
      not exists(g.(Ruby::Call).getMethod().(Ruby::ScopeResolution).getScope())
    ) and
    child = SynthChild(SelfKind(TSelfVariable(scopeOf(toGenerated(mc)).getEnclosingSelfScope()))) and
    i = 0
  }

  private class RegularMethodCallSelfSynthesis extends Synthesis {
    final override predicate child(AstNode parent, int i, Child child) {
      regularMethodCallSelfSynthesis(parent, i, child)
    }
  }
}

private module SetterDesugar {
  /** An assignment where the left-hand side is a method call. */
  private class SetterAssignExpr extends AssignExpr {
    private MethodCall mc;

    pragma[nomagic]
    SetterAssignExpr() { mc = this.getLeftOperand() }

    MethodCall getMethodCall() { result = mc }

    pragma[nomagic]
    MethodCallKind getCallKind(boolean setter, int arity) {
      result = MethodCallKind(mc.getMethodName(), setter, arity)
    }

    pragma[nomagic]
    Expr getReceiver() { result = mc.getReceiver() }

    pragma[nomagic]
    Expr getArgument(int i) { result = mc.getArgument(i) }

    pragma[nomagic]
    int getNumberOfArguments() { result = mc.getNumberOfArguments() }

    pragma[nomagic]
    Location getMethodCallLocation() { hasLocation(mc, result) }
  }

  pragma[nomagic]
  private predicate setterMethodCallSynthesis(AstNode parent, int i, Child child) {
    exists(SetterAssignExpr sae |
      parent = sae and
      i = -1 and
      child = SynthChild(StmtSequenceKind())
      or
      exists(AstNode seq | seq = TStmtSequenceSynth(sae, -1) |
        parent = seq and
        i = 0 and
        child = SynthChild(sae.getCallKind(true, sae.getNumberOfArguments() + 1))
        or
        exists(AstNode call | call = TMethodCallSynth(seq, 0, _, _, _) |
          parent = call and
          i = 0 and
          child = childRef(sae.getReceiver())
          or
          parent = call and
          child = childRef(sae.getArgument(i - 1))
          or
          exists(int valueIndex | valueIndex = sae.getNumberOfArguments() + 1 |
            parent = call and
            i = valueIndex and
            child = SynthChild(AssignExprKind())
            or
            parent = TAssignExprSynth(call, valueIndex) and
            (
              i = 0 and
              child = SynthChild(LocalVariableAccessSynthKind(TLocalVariableSynth(sae, 0)))
              or
              i = 1 and
              child = childRef(sae.getRightOperand())
            )
          )
        )
        or
        parent = seq and
        i = 1 and
        child = SynthChild(LocalVariableAccessSynthKind(TLocalVariableSynth(sae, 0)))
      )
    )
  }

  /**
   * ```rb
   * x.foo = y
   * ```
   *
   * desugars to
   *
   * ```rb
   * x.foo=(__synth_0 = y);
   * __synth_0;
   * ```
   */
  private class SetterMethodCallSynthesis extends Synthesis {
    final override predicate child(AstNode parent, int i, Child child) {
      setterMethodCallSynthesis(parent, i, child)
    }

    final override predicate location(AstNode n, Location l) {
      exists(SetterAssignExpr sae, StmtSequence seq |
        seq = sae.getDesugared() and
        l = sae.getMethodCallLocation() and
        n = seq.getAStmt()
      )
    }

    final override predicate excludeFromControlFlowTree(AstNode n) {
      n = any(SetterAssignExpr sae).getMethodCall()
    }

    final override predicate localVariable(AstNode n, int i) {
      n instanceof SetterAssignExpr and
      i = 0
    }

    final override predicate methodCall(string name, boolean setter, int arity) {
      exists(SetterAssignExpr sae |
        name = sae.getMethodCall().getMethodName() and
        setter = true and
        arity = sae.getNumberOfArguments() + 1
      )
    }
  }
}

private module AssignOperationDesugar {
  /**
   * Gets the operator kind to synthesize for operator assignment `ao`.
   */
  private SynthKind getKind(AssignOperation ao) {
    ao instanceof AssignAddExpr and result = AddExprKind()
    or
    ao instanceof AssignSubExpr and result = SubExprKind()
    or
    ao instanceof AssignMulExpr and result = MulExprKind()
    or
    ao instanceof AssignDivExpr and result = DivExprKind()
    or
    ao instanceof AssignModuloExpr and result = ModuloExprKind()
    or
    ao instanceof AssignExponentExpr and result = ExponentExprKind()
    or
    ao instanceof AssignLogicalAndExpr and result = LogicalAndExprKind()
    or
    ao instanceof AssignLogicalOrExpr and result = LogicalOrExprKind()
    or
    ao instanceof AssignLShiftExpr and result = LShiftExprKind()
    or
    ao instanceof AssignRShiftExpr and result = RShiftExprKind()
    or
    ao instanceof AssignBitwiseAndExpr and result = BitwiseAndExprKind()
    or
    ao instanceof AssignBitwiseOrExpr and result = BitwiseOrExprKind()
    or
    ao instanceof AssignBitwiseXorExpr and result = BitwiseXorExprKind()
  }

  private Location getAssignOperationLocation(AssignOperation ao) {
    exists(Ruby::OperatorAssignment g, Ruby::Token op |
      g = toGenerated(ao) and
      op.getParent() = g and
      op.getParentIndex() = 1 and
      result = op.getLocation()
    )
  }

  /** An assignment operation where the left-hand side is a variable. */
  private class VariableAssignOperation extends AssignOperation {
    private Variable v;

    pragma[nomagic]
    VariableAssignOperation() { v = this.getLeftOperand().(VariableAccess).getVariable() }

    pragma[nomagic]
    SynthKind getVariableAccessKind() {
      result in [
          LocalVariableAccessRealKind(v).(SynthKind), InstanceVariableAccessKind(v),
          ClassVariableAccessKind(v), GlobalVariableAccessKind(v)
        ]
    }
  }

  pragma[nomagic]
  private predicate variableAssignOperationSynthesis(AstNode parent, int i, Child child) {
    exists(VariableAssignOperation vao |
      parent = vao and
      i = -1 and
      child = SynthChild(AssignExprKind())
      or
      exists(AstNode assign | assign = TAssignExprSynth(vao, -1) |
        parent = assign and
        i = 0 and
        child = childRef(vao.getLeftOperand())
        or
        parent = assign and
        i = 1 and
        child = SynthChild(getKind(vao))
        or
        parent = getSynthChild(assign, 1) and
        (
          i = 0 and
          child = SynthChild(vao.getVariableAccessKind())
          or
          i = 1 and
          child = childRef(vao.getRightOperand())
        )
      )
    )
  }

  /**
   * ```rb
   * x += y
   * ```
   *
   * desugars to
   *
   * ```rb
   * x = x + y
   * ```
   *
   * when `x` is a variable.
   */
  private class VariableAssignOperationSynthesis extends Synthesis {
    final override predicate child(AstNode parent, int i, Child child) {
      variableAssignOperationSynthesis(parent, i, child)
    }

    final override predicate location(AstNode n, Location l) {
      exists(VariableAssignOperation vao, BinaryOperation bo |
        bo = vao.getDesugared().(AssignExpr).getRightOperand()
      |
        n = bo and
        l = getAssignOperationLocation(vao)
        or
        n = bo.getLeftOperand() and
        hasLocation(vao.getLeftOperand(), l)
      )
    }
  }

  /** An assignment operation where the left-hand side is a method call. */
  private class SetterAssignOperation extends AssignOperation {
    private MethodCall mc;

    pragma[nomagic]
    SetterAssignOperation() { mc = this.getLeftOperand() }

    MethodCall getMethodCall() { result = mc }

    pragma[nomagic]
    MethodCallKind getCallKind(boolean setter, int arity) {
      result = MethodCallKind(mc.getMethodName(), setter, arity)
    }

    pragma[nomagic]
    Expr getReceiver() { result = mc.getReceiver() }

    pragma[nomagic]
    Expr getArgument(int i) { result = mc.getArgument(i) }

    pragma[nomagic]
    int getNumberOfArguments() { result = mc.getNumberOfArguments() }

    pragma[nomagic]
    Location getMethodCallLocation() { hasLocation(mc, result) }
  }

  pragma[nomagic]
  private predicate methodCallAssignOperationSynthesis(AstNode parent, int i, Child child) {
    exists(SetterAssignOperation sao |
      parent = sao and
      i = -1 and
      child = SynthChild(StmtSequenceKind())
      or
      exists(AstNode seq | seq = TStmtSequenceSynth(sao, -1) |
        // `__synth__0 = foo`
        assign(parent, i, child, TLocalVariableSynth(sao, 0), seq, 0, sao.getReceiver())
        or
        // `__synth__1 = bar`
        exists(Expr arg, int j | arg = sao.getArgument(j - 1) |
          assign(parent, i, child, TLocalVariableSynth(sao, j), seq, j, arg)
        )
        or
        // `__synth__2 = __synth__0.[](__synth__1) + y`
        exists(int opAssignIndex | opAssignIndex = sao.getNumberOfArguments() + 1 |
          parent = seq and
          i = opAssignIndex and
          child = SynthChild(AssignExprKind())
          or
          exists(AstNode assign | assign = TAssignExprSynth(seq, opAssignIndex) |
            parent = assign and
            i = 0 and
            child =
              SynthChild(LocalVariableAccessSynthKind(TLocalVariableSynth(sao, opAssignIndex)))
            or
            parent = assign and
            i = 1 and
            child = SynthChild(getKind(sao))
            or
            // `__synth__0.[](__synth__1) + y`
            exists(AstNode op | op = getSynthChild(assign, 1) |
              parent = op and
              i = 0 and
              child = SynthChild(sao.getCallKind(false, sao.getNumberOfArguments()))
              or
              parent = TMethodCallSynth(op, 0, _, _, _) and
              child = SynthChild(LocalVariableAccessSynthKind(TLocalVariableSynth(sao, i))) and
              i in [0 .. sao.getNumberOfArguments()]
              or
              parent = op and
              i = 1 and
              child = childRef(sao.getRightOperand())
            )
          )
          or
          // `__synth__0.[]=(__synth__1, __synth__2);`
          parent = seq and
          i = opAssignIndex + 1 and
          child = SynthChild(sao.getCallKind(true, opAssignIndex))
          or
          exists(AstNode setter | setter = TMethodCallSynth(seq, opAssignIndex + 1, _, _, _) |
            parent = setter and
            child = SynthChild(LocalVariableAccessSynthKind(TLocalVariableSynth(sao, i))) and
            i in [0 .. sao.getNumberOfArguments()]
            or
            parent = setter and
            i = opAssignIndex + 1 and
            child =
              SynthChild(LocalVariableAccessSynthKind(TLocalVariableSynth(sao, opAssignIndex)))
          )
          or
          parent = seq and
          i = opAssignIndex + 2 and
          child = SynthChild(LocalVariableAccessSynthKind(TLocalVariableSynth(sao, opAssignIndex)))
        )
      )
    )
  }

  /**
   * ```rb
   * foo[bar] += y
   * ```
   *
   * desugars to
   *
   * ```rb
   * __synth__0 = foo;
   * __synth__1 = bar;
   * __synth__2 = __synth__0.[](__synth__1) + y;
   * __synth__0.[]=(__synth__1, __synth__2);
   * __synth__2;
   * ```
   */
  private class MethodCallAssignOperationSynthesis extends Synthesis {
    final override predicate child(AstNode parent, int i, Child child) {
      methodCallAssignOperationSynthesis(parent, i, child)
    }

    final override predicate location(AstNode n, Location l) {
      exists(SetterAssignOperation sao, StmtSequence seq | seq = sao.getDesugared() |
        n = seq.getStmt(0) and
        hasLocation(sao.getReceiver(), l)
        or
        exists(int i |
          n = seq.getStmt(i + 1) and
          hasLocation(sao.getArgument(i), l)
        )
        or
        exists(AssignExpr ae, int opAssignIndex |
          opAssignIndex = sao.getNumberOfArguments() + 1 and
          ae = seq.getStmt(opAssignIndex)
        |
          l = getAssignOperationLocation(sao) and
          n = ae
          or
          exists(BinaryOperation bo | bo = ae.getRightOperand() |
            n = bo.getLeftOperand() and
            l = sao.getMethodCallLocation()
            or
            exists(MethodCall mc | mc = bo.getLeftOperand() |
              n = mc.getReceiver() and
              hasLocation(sao.getReceiver(), l)
              or
              exists(int i |
                n = mc.getArgument(i) and
                hasLocation(sao.getArgument(i), l)
              )
            )
          )
          or
          exists(MethodCall mc | mc = seq.getStmt(opAssignIndex + 1) |
            n = mc and
            l = sao.getMethodCallLocation()
            or
            n = mc.getReceiver() and
            hasLocation(sao.getReceiver(), l)
            or
            exists(int i | n = mc.getArgument(i) |
              hasLocation(sao.getArgument(i), l)
              or
              i = opAssignIndex and
              l = getAssignOperationLocation(sao)
            )
          )
          or
          n = seq.getStmt(opAssignIndex + 2) and
          l = getAssignOperationLocation(sao)
        )
      )
    }

    final override predicate localVariable(AstNode n, int i) {
      n = any(SetterAssignOperation sao | i in [0 .. sao.getNumberOfArguments() + 1])
    }

    final override predicate methodCall(string name, boolean setter, int arity) {
      exists(SetterAssignOperation sao | name = sao.getMethodCall().getMethodName() |
        setter = false and
        arity = sao.getNumberOfArguments()
        or
        setter = true and
        arity = sao.getNumberOfArguments() + 1
      )
    }

    final override predicate excludeFromControlFlowTree(AstNode n) {
      n = any(SetterAssignOperation sao).getMethodCall()
    }
  }
}

private module CompoundAssignDesugar {
  /** An assignment where the left-hand side is a tuple pattern. */
  private class TupleAssignExpr extends AssignExpr {
    private TuplePattern tp;

    pragma[nomagic]
    TupleAssignExpr() { tp = this.getLeftOperand() }

    TuplePattern getTuplePattern() { result = tp }

    pragma[nomagic]
    Pattern getElement(int i) { result = tp.getElement(i) }

    pragma[nomagic]
    int getNumberOfElements() {
      toGenerated(tp) = any(TuplePatternImpl impl | result = count(impl.getChildNode(_)))
    }

    pragma[nomagic]
    int getRestIndexOrNumberOfElements() {
      result = tp.getRestIndex()
      or
      toGenerated(tp) = any(TuplePatternImpl impl | not exists(impl.getRestIndex())) and
      result = this.getNumberOfElements()
    }
  }

  pragma[nomagic]
  private predicate compoundAssignSynthesis(AstNode parent, int i, Child child) {
    exists(TupleAssignExpr tae |
      parent = tae and
      i = -1 and
      child = SynthChild(StmtSequenceKind())
      or
      exists(AstNode seq | seq = TStmtSequenceSynth(tae, -1) |
        parent = seq and
        i = 0 and
        child = SynthChild(AssignExprKind())
        or
        exists(AstNode assign | assign = TAssignExprSynth(seq, 0) |
          parent = assign and
          i = 0 and
          child = SynthChild(LocalVariableAccessSynthKind(TLocalVariableSynth(tae, 0)))
          or
          parent = assign and
          i = 1 and
          child = SynthChild(SplatExprKind())
          or
          parent = TSplatExprSynth(assign, 1) and
          i = 0 and
          child = childRef(tae.getRightOperand())
        )
        or
        exists(Pattern p, int j, int restIndex |
          p = tae.getElement(j) and
          restIndex = tae.getRestIndexOrNumberOfElements()
        |
          parent = seq and
          i = j + 1 and
          child = SynthChild(AssignExprKind())
          or
          exists(AstNode assign | assign = TAssignExprSynth(seq, j + 1) |
            parent = assign and
            i = 0 and
            child = childRef(p)
            or
            parent = assign and
            i = 1 and
            child = SynthChild(MethodCallKind("[]", false, 1))
            or
            parent = TMethodCallSynth(assign, 1, _, _, _) and
            i = 0 and
            child = SynthChild(LocalVariableAccessSynthKind(TLocalVariableSynth(tae, 0)))
            or
            j < restIndex and
            parent = TMethodCallSynth(assign, 1, _, _, _) and
            i = 1 and
            child = SynthChild(IntegerLiteralKind(j))
            or
            j = restIndex and
            (
              parent = TMethodCallSynth(assign, 1, _, _, _) and
              i = 1 and
              child = SynthChild(RangeLiteralKind(true))
              or
              exists(AstNode call |
                call = TMethodCallSynth(assign, 1, _, _, _) and
                parent = TRangeLiteralSynth(call, 1, _)
              |
                i = 0 and
                child = SynthChild(IntegerLiteralKind(j))
                or
                i = 1 and
                child = SynthChild(IntegerLiteralKind(restIndex - tae.getNumberOfElements()))
              )
            )
            or
            j > restIndex and
            parent = TMethodCallSynth(assign, 1, _, _, _) and
            i = 1 and
            child = SynthChild(IntegerLiteralKind(j - tae.getNumberOfElements()))
          )
        )
      )
    )
  }

  /**
   * ```rb
   * x, *y, z = w
   * ```
   * desugars to
   *
   * ```rb
   * __synth__0 = *w;
   * x = __synth__0[0];
   * y = __synth__0[1..-2];
   * z = __synth__0[-1];
   * ```
   */
  private class CompoundAssignSynthesis extends Synthesis {
    final override predicate child(AstNode parent, int i, Child child) {
      compoundAssignSynthesis(parent, i, child)
    }

    final override predicate location(AstNode n, Location l) {
      exists(TupleAssignExpr tae, StmtSequence seq | seq = tae.getDesugared() |
        n = seq.getStmt(0) and
        hasLocation(tae.getRightOperand(), l)
        or
        exists(Pattern p, int j |
          p = tae.getElement(j) and
          n = seq.getStmt(j + 1) and
          hasLocation(p, l)
        )
      )
    }

    final override predicate localVariable(AstNode n, int i) {
      n instanceof TupleAssignExpr and
      i = 0
    }

    final override predicate methodCall(string name, boolean setter, int arity) {
      name = "[]" and
      setter = false and
      arity = 1
    }

    final override predicate excludeFromControlFlowTree(AstNode n) {
      n = any(TupleAssignExpr tae).getTuplePattern()
    }
  }
}

private module ArrayLiteralDesugar {
  pragma[nomagic]
  private predicate arrayLiteralSynthesis(AstNode parent, int i, Child child) {
    exists(ArrayLiteral al |
      parent = al and
      i = -1 and
      child = SynthChild(MethodCallKind("[]", false, al.getNumberOfElements() + 1))
      or
      exists(AstNode mc | mc = TMethodCallSynth(al, -1, _, _, _) |
        parent = mc and
        i = 0 and
        child = SynthChild(ConstantReadAccessKind("::Array"))
        or
        parent = mc and
        child = childRef(al.getElement(i - 1))
      )
    )
  }

  /**
   * ```rb
   * [1, 2, 3]
   * ```
   * desugars to
   *
   * ```rb
   * ::Array.[](1, 2, 3)
   * ```
   */
  private class CompoundAssignSynthesis extends Synthesis {
    final override predicate child(AstNode parent, int i, Child child) {
      arrayLiteralSynthesis(parent, i, child)
    }

    final override predicate methodCall(string name, boolean setter, int arity) {
      name = "[]" and
      setter = false and
      arity = any(ArrayLiteral al).getNumberOfElements() + 1
    }

    final override predicate constantReadAccess(string name) { name = "::Array" }
  }
}

/**
 * ```rb
 * for x in xs
 *   <loop_body>
 * end
 * ```
 * desugars to, roughly,
 * ```rb
 * xs.each { |__synth__0| x = __synth__0; <loop_body> }
 * ```
 *
 * Note that for-loops, unlike blocks, do not create a new variable scope, so
 * variables within this block inherit the enclosing scope. The exception to
 * this is the synthesized variable declared by the block parameter, which is
 * scoped to the synthesized block.
 */
private module ForLoopDesugar {
  pragma[nomagic]
  private predicate forLoopSynthesis(AstNode parent, int i, Child child) {
    exists(ForExpr for |
      // each call
      parent = for and
      i = -1 and
      child = SynthChild(MethodCallKind("each", false, 0))
      or
      exists(MethodCall eachCall | eachCall = TMethodCallSynth(for, -1, "each", false, 0) |
        // receiver
        parent = eachCall and
        i = 0 and
        child = childRef(for.getValue()) // value is the Enumerable
        or
        parent = eachCall and
        i = -2 and
        child = SynthChild(BraceBlockKind())
        or
        exists(Block block | block = TBraceBlockSynth(eachCall, -2) |
          // block params
          parent = block and
          i = 0 and
          child = SynthChild(SimpleParameterKind())
          or
          exists(SimpleParameter param | param = TSimpleParameterSynth(block, 0) |
            parent = param and
            i = 0 and
            child = SynthChild(LocalVariableAccessSynthKind(TLocalVariableSynth(param, 0)))
            or
            // assignment to pattern from for loop to synth parameter
            parent = block and
            i = 1 and
            child = SynthChild(AssignExprKind())
            or
            parent = TAssignExprSynth(block, 1) and
            (
              i = 0 and
              child = childRef(for.getPattern())
              or
              i = 1 and
              child = SynthChild(LocalVariableAccessSynthKind(TLocalVariableSynth(param, 0)))
            )
          )
          or
          // rest of block body
          parent = block and
          child = childRef(for.getBody().(Do).getStmt(i - 2))
        )
      )
    )
  }

  private class ForLoopSynthesis extends Synthesis {
    final override predicate child(AstNode parent, int i, Child child) {
      forLoopSynthesis(parent, i, child)
    }

    final override predicate methodCall(string name, boolean setter, int arity) {
      name = "each" and
      setter = false and
      arity = 0
    }

    final override predicate localVariable(AstNode n, int i) {
      n instanceof TSimpleParameterSynth and
      i = 0
    }

    final override predicate excludeFromControlFlowTree(AstNode n) {
      n = any(ForExpr for).getBody()
    }
  }
}
