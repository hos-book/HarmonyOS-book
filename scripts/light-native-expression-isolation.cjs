// Looping native functions use the existing bounded taskpool host, including sources without JS.
module.exports = function nativeExpressionIsolation(name, text) {
  const replace = (before, after) => {
    if (text.split(before).length !== 2) throw new Error(`Upstream native expression path changed: ${name}`);
    text = text.replace(before, after);
  };
  if (name === 'core/nativesource/NativeExpr.ts') {
    replace('/** Inspect the parsed expression without evaluating it. Only JS calls need an isolated script host. */',
      '/** Inspect dependencies without evaluating. JS calls and library loops need the bounded host. */');
    replace('      const node = nodes.pop() as Node;\n      if (node.t === \'call\') {',
      '      const node = nodes.pop() as Node;\n' +
      '      // Pure library functions can still spend hundreds of milliseconds in a loop.\n' +
      "      if (node.t === 'for' || node.t === 'while') { required = true; break; }\n" +
      "      if (node.t === 'call') {");
  }
  if (name === 'core/nativesource/NativeSourceRunner.ts') {
    replace('/** Batch pure JS field expressions so a page does not serialize the full response once per field. */',
      '/** Batch isolated field expressions so a page does not serialize the full response once per field. */');
    replace('    if (!this.definition.js || !this.host.evaluateExpression) return [];',
      '    if (!this.host.evaluateExpression) return [];');
    replace('    if (this.definition.js && this.host.evaluateExpression && this.expr.requiresScript(text, template)) {\n' +
      "      return this.host.evaluateExpression(this.definition.js, this.definition.lib || '', text, scope.snapshot(),",
      '    if (this.host.evaluateExpression && this.expr.requiresScript(text, template)) {\n' +
      "      return this.host.evaluateExpression(this.definition.js || '', this.definition.lib || '', text, scope.snapshot(),");
    replace('    // 表达式不送后台：求值本身很快，送过去却要把整个作用域（含整页正文、登录信息）序列化一遍。',
      '    // 小型纯表达式直接求值；含函数库循环或 JS 调用时复用上面的有界后台宿主。');
  }
  return text;
};
