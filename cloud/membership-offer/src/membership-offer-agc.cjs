// AGC Node.js 20 event runtime: secrets come from context.env, results use callback.
let handler;
exports.handler = async (event, context, callback) => {
  try {
    handler ??= import('./membership-offer-function.mjs').then(module =>
      module.createMembershipOfferHandler(context.env));
    const reply = await (await handler)(event);
    const body = JSON.parse(reply.body);
    const response = new context.HTTPResponse(body, reply.headers, 'application/json', String(reply.statusCode));
    response.body = body;
    callback(response);
  } catch {
    // Do not log event bodies, JWTs, environment variables or signing errors.
    const body = { code: 'OFFER_UNAVAILABLE' };
    const response = new context.HTTPResponse(body, { 'Cache-Control': 'no-store' }, 'application/json', '503');
    response.body = body;
    callback(response);
  }
};
