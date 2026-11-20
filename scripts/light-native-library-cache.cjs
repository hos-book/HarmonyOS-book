// Keep the imported parser reproducible: share syntax only, never an evaluator or source state.
module.exports = function nativeLibraryCache(text) {
  const replace = (before, after) => {
    if (text.split(before).length !== 2) throw new Error('Upstream native library parser changed');
    text = text.replace(before, after);
  };
  replace('  private static parseLibrary(source: string): FunctionDecl[] {\n    const functions = new Parser(tokenize(source || \'\')).parseLibrary();',
`  private static libraryCache: Map<string, { functions: FunctionDecl[], tokens: number }> = new Map();
  private static libraryChars: number = 0;
  private static libraryTokens: number = 0;

  private static parseLibrary(source: string): FunctionDecl[] {
    const cached = NativeExpr.libraryCache.get(source);
    if (cached !== undefined) {
      NativeExpr.libraryCache.delete(source);
      NativeExpr.libraryCache.set(source, cached);
      return cached.functions;
    }
    const tokens = tokenize(source || '');
    const functions = new Parser(tokens).parseLibrary();`);
  replace('      seen.add(fn.name);\n    }\n    return functions;\n  }',
`      seen.add(fn.name);
    }
    // Validation and execution reuse immutable syntax. Each NativeExpr still owns its
    // function map, host, scope, script dependencies, step counter and call depth.
    if (source.length <= 2 * 1024 * 1024 && tokens.length <= 100000) {
      while (NativeExpr.libraryCache.size >= 64 ||
        NativeExpr.libraryChars + source.length > 2 * 1024 * 1024 ||
        NativeExpr.libraryTokens + tokens.length > 100000) {
        const oldest = NativeExpr.libraryCache.keys().next().value;
        if (oldest === undefined) break;
        NativeExpr.libraryChars -= oldest.length;
        NativeExpr.libraryTokens -= NativeExpr.libraryCache.get(oldest)!.tokens;
        NativeExpr.libraryCache.delete(oldest);
      }
      NativeExpr.libraryCache.set(source, { functions, tokens: tokens.length });
      NativeExpr.libraryChars += source.length;
      NativeExpr.libraryTokens += tokens.length;
    }
    return functions;
  }`);
  // Most tokens are one-character operators; preserve the original longest-match order.
  replace("const KEYWORDS = ['fn', 'let', 'if', 'else', 'for', 'in', 'while', 'return', 'break', 'continue'];",
`const OPERATORS_BY_FIRST: Map<string, string[]> = new Map();
for (const op of OPERATORS) {
  const choices = OPERATORS_BY_FIRST.get(op[0]) || [];
  choices.push(op);
  OPERATORS_BY_FIRST.set(op[0], choices);
}
const KEYWORDS = ['fn', 'let', 'if', 'else', 'for', 'in', 'while', 'return', 'break', 'continue'];`);
  replace('    for (const op of OPERATORS) {', '    for (const op of OPERATORS_BY_FIRST.get(ch) || []) {');
  return text;
};
