/**
 * Contains predicates and classes relating to support methods for tests, such as the `source()` and `sink()`.
 */

import java
private import semmle.code.java.dataflow.internal.DataFlowUtil
private import semmle.code.java.dataflow.ExternalFlow
private import semmle.code.java.dataflow.FlowSummary
private import semmle.code.java.dataflow.internal.FlowSummaryImpl
private import FlowTestCaseUtils
private import FlowTestCase

/**
 * Returns a valid Java token naming the field `fc`.
 */
private string getFieldToken(FieldContent fc) {
  result =
    fc.getField().getDeclaringType().getSourceDeclaration().getName() + "_" +
      fc.getField().getName()
}

/**
 * Returns a valid Java token naming the synthetic field `fc`,
 * assuming that the name of that field consists only of characters valid in a Java identifier and `.`.
 */
private string getSyntheticFieldToken(SyntheticFieldContent fc) {
  exists(string name, int parts |
    name = fc.getField() and
    parts = count(name.splitAt("."))
  |
    if parts = 1
    then result = name
    else result = name.splitAt(".", parts - 2) + "_" + name.splitAt(".", parts - 1)
  )
}

/**
 * Returns a token suitable for incorporation into a Java method name describing content `c`.
 */
private string contentToken(Content c) {
  c instanceof ArrayContent and result = "ArrayElement"
  or
  c instanceof CollectionContent and result = "Element"
  or
  c instanceof MapKeyContent and result = "MapKey"
  or
  c instanceof MapValueContent and result = "MapValue"
  or
  result = getFieldToken(c)
  or
  result = getSyntheticFieldToken(c)
}

/**
 * Returns the `content` wrapped by `component`, if any.
 */
private Content getContent(SummaryComponent component) {
  component = SummaryComponent::content(result)
}

/** Contains utility predicates for getting relevant support methods. */
module SupportMethod {
  /** Gets a generator method for the content type of the head of the component stack `c`. */
  GenMethod genMethodForContent(SummaryComponentStack c) {
    result = genMethodFor(any(VoidType v), c)
  }

  /** Gets a generator method for the type `t` and the content type of the head of the component stack `c`. */
  GenMethod genMethodFor(Type t, SummaryComponentStack c) {
    result =
      min(GenMethod g |
        g = min(GenMethod g1 | g1.appliesTo(t, getContent(c.head())) | g1 order by g1.getPriority())
      )
  }

  /** Gets a getter method for the content type of the head of the component stack `c`. */
  GetMethod getMethodForContent(SummaryComponentStack c) {
    result = getMethodFor(any(VoidType v), c)
  }

  /** Gets a getter method for the type `t` and the content type of the head of the component stack `c`. */
  GetMethod getMethodFor(Type t, SummaryComponentStack c) {
    result =
      min(GetMethod g |
        g = min(GetMethod g1 | g1.appliesTo(t, getContent(c.head())) | g1 order by g1.getPriority())
      )
  }
}

/**
 * A support method for tests, such as `source()` or `sink()`.
 */
bindingset[this]
abstract class SupportMethod extends string {
  /** Gets an import that is required for this support method. */
  string getARequiredImport() { none() }

  /** Gets the Java definition of this support method, if one is necessary. */
  string getDefinition() { none() }

  /** Gets the priority of this support method. Lower priorities are preferred when multiple support methods apply. */
  bindingset[this]
  int getPriority() { result = 50 }

  /**
   * Gets the CSV row describing this support method if it is needed to set up the output for this test.
   *
   * For example, `newWithMapValue` will propagate a value from `Argument[0]` to `MapValue of ReturnValue`, and `getMapValue`
   * will do the opposite.
   */
  string getCsvModel() { none() }
}

/**
 * The method `source()` which is considered as the source for the flow test.
 */
class SourceMethod extends SupportMethod {
  SourceMethod() { this = "source" }

  override string getDefinition() { result = "Object source() { return null; }" }
}

/**
 * The method `sink()` which is considered as the sink for the flow test.
 */
class SinkMethod extends SupportMethod {
  SinkMethod() { this = "sink" }

  override string getDefinition() { result = "void sink(Object o) { }" }
}

/**
 * A method for getting content from a type.
 */
bindingset[this]
abstract class GetMethod extends SupportMethod {
  /**
   * Holds if this get method can be used to get the content `c` from the type `t`.
   */
  abstract predicate appliesTo(Type t, Content c);

  /**
   * Gets the call to get the content from the argument `arg`.
   */
  bindingset[this, arg]
  abstract string getCall(string arg);
}

private class DefaultGetMethod extends GetMethod {
  Content c;

  DefaultGetMethod() { this = "DefaultGet" + contentToken(c) }

  string getName() { result = "get" + contentToken(c) }

  override int getPriority() { result = 999 }

  override predicate appliesTo(Type t, Content c1) {
    c = c1 and
    // suppress unused variable warning
    t = [any(TestCase tc).getOutputType(), any(VoidType v)]
  }

  bindingset[arg]
  override string getCall(string arg) { result = this.getName() + "(" + arg + ")" }

  override string getDefinition() {
    result = "Object get" + contentToken(c) + "(Object container) { return null; }"
  }

  override string getCsvModel() {
    result =
      "generatedtest;Test;false;" + this.getName() + ";;;" +
        getComponentSpec(SummaryComponent::content(c)) + " of Argument[0];ReturnValue;value"
  }
}

private class ListGetMethod extends GetMethod {
  ListGetMethod() { this = "listgetmethod" }

  override predicate appliesTo(Type t, Content c) {
    t.(RefType).getASourceSupertype*().hasQualifiedName("java.lang", "Iterable") and
    c instanceof CollectionContent
  }

  override string getDefinition() {
    result = "<T> T getElement(Iterable<T> it) { return it.iterator().next(); }"
  }

  bindingset[arg]
  override string getCall(string arg) { result = "getElement(" + arg + ")" }
}

private class IteratorGetMethod extends GetMethod {
  IteratorGetMethod() { this = "iteratorgetmethod" }

  override predicate appliesTo(Type t, Content c) {
    t.(RefType).getASourceSupertype*().hasQualifiedName("java.util", "Iterator") and
    c instanceof CollectionContent
  }

  override string getDefinition() {
    result = "<T> T getElement(Iterator<T> it) { return it.next(); }"
  }

  bindingset[arg]
  override string getCall(string arg) { result = "getElement(" + arg + ")" }
}

private class OptionalGetMethod extends GetMethod {
  OptionalGetMethod() { this = "optionalgetmethod" }

  override predicate appliesTo(Type t, Content c) {
    t.(RefType).getSourceDeclaration().hasQualifiedName("java.util", "Optional") and
    c instanceof CollectionContent
  }

  override string getDefinition() { result = "<T> T getElement(Optional<T> o) { return o.get(); }" }

  bindingset[arg]
  override string getCall(string arg) { result = "getElement(" + arg + ")" }
}

private class MapGetKeyMethod extends GetMethod {
  MapGetKeyMethod() { this = "mapgetkeymethod" }

  override predicate appliesTo(Type t, Content c) {
    t.(RefType).getASourceSupertype*().hasQualifiedName("java.util", "Map") and
    c instanceof MapKeyContent
  }

  override string getDefinition() {
    result = "<K> K getMapKey(Map<K,?> map) { return map.keySet().iterator().next(); }"
  }

  bindingset[arg]
  override string getCall(string arg) { result = "getMapKey(" + arg + ")" }
}

private class MapValueGetMethod extends GetMethod {
  MapValueGetMethod() { this = "MapValueGetMethod" }

  override predicate appliesTo(Type t, Content c) {
    t.(RefType).getASourceSupertype*().hasQualifiedName("java.util", "Map") and
    c instanceof MapValueContent
  }

  override string getDefinition() {
    result = "<V> V getMapValue(Map<?,V> map) { return map.get(null); }"
  }

  bindingset[arg]
  override string getCall(string arg) { result = "getMapValue(" + arg + ")" }
}

private class ArrayGetMethod extends GetMethod {
  ArrayGetMethod() { this = "arraygetmethod" }

  override predicate appliesTo(Type t, Content c) {
    t instanceof Array and
    c instanceof ArrayContent
  }

  override string getDefinition() {
    result = "<T> T getArrayElement(T[] array) { return array[0]; }"
  }

  bindingset[arg]
  override string getCall(string arg) { result = "getArrayElement(" + arg + ")" }
}

/**
 * A method for generating a type with content.
 */
bindingset[this]
abstract class GenMethod extends SupportMethod {
  /**
   * Holds if this generator method can be used to generate a new `t` that contains content `c`.
   */
  abstract predicate appliesTo(Type t, Content c);

  /**
   * Gets the call to generate an object with content `arg`.
   */
  bindingset[this, arg]
  abstract string getCall(string arg);
}

private class DefaultGenMethod extends GenMethod {
  Content c;

  DefaultGenMethod() { this = "DefaultGen" + contentToken(c) }

  string getName() { result = "newWith" + contentToken(c) }

  override int getPriority() { result = 999 }

  override predicate appliesTo(Type t, Content c1) {
    c = c1 and
    // suppress unused variable warning
    t = [any(TestCase tc).getInputType(), any(VoidType v)]
  }

  bindingset[arg]
  override string getCall(string arg) { result = this.getName() + "(" + arg + ")" }

  override string getDefinition() {
    result = "Object newWith" + contentToken(c) + "(Object element) { return null; }"
  }

  override string getCsvModel() {
    result =
      "generatedtest;Test;false;" + this.getName() + ";;;Argument[0];" +
        getComponentSpec(SummaryComponent::content(c)) + " of ReturnValue;value"
  }
}

private class ListGenMethod extends GenMethod {
  ListGenMethod() { this = "listgenmethod" }

  override predicate appliesTo(Type t, Content c) {
    exists(GenericType list | list.hasQualifiedName("java.util", "List") |
      t = list or list.getAParameterizedType().getASupertype*() = t
    ) and
    c instanceof CollectionContent
  }

  bindingset[arg]
  override string getCall(string arg) { result = "List.of(" + arg + ")" }
}

private class OptionalGenMethod extends GenMethod {
  OptionalGenMethod() { this = "optionalgenmethod" }

  override predicate appliesTo(Type t, Content c) {
    exists(GenericType list | list.hasQualifiedName("java.util", "List") |
      list.getAParameterizedType().getASupertype*() = t
    ) and
    c instanceof CollectionContent
  }

  bindingset[arg]
  override string getCall(string arg) { result = "Optional.of(" + arg + ")" }
}

private class MapGenKeyMethod extends GenMethod {
  MapGenKeyMethod() { this = "mapkeygenmethod" }

  override predicate appliesTo(Type t, Content c) {
    exists(GenericType map | map.hasQualifiedName("java.util", "Map") |
      map.getAParameterizedType().getASupertype*() = t
    ) and
    c instanceof MapKeyContent
  }

  bindingset[arg]
  override string getCall(string arg) { result = "Map.of(" + arg + ", null)" }
}

private class MapGenValueMethod extends GenMethod {
  MapGenValueMethod() { this = "mapvaluegenmethod" }

  override predicate appliesTo(Type t, Content c) {
    exists(GenericType map | map.hasQualifiedName("java.util", "Map") |
      map.getAParameterizedType().getASupertype*() = t
    ) and
    c instanceof MapValueContent
  }

  bindingset[arg]
  override string getCall(string arg) { result = "Map.of(null, " + arg + ")" }
}

string getConvertExprIfNotObject(RefType t) {
  if t.hasQualifiedName("java.lang", "Object")
  then result = ""
  else result = "(" + getShortNameIfPossible(t) + ")"
}

private class ArrayGenMethod extends GenMethod {
  Array type;

  ArrayGenMethod() { this = type.getName() + "genmethod" }

  override predicate appliesTo(Type t, Content c) {
    replaceTypeVariable(t.(Array).getComponentType()) = type.getComponentType() and
    c instanceof ArrayContent
  }

  bindingset[arg]
  override string getCall(string arg) {
    result = "new " + getShortNameIfPossible(type) + "{" + getConvertExprIfNotObject(type.getComponentType()) + arg + "}"
  }
}
