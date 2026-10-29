/** Escape a value read from a graph file before interpolating it into HTML. */
export const escapeHtml = (value: string | number) =>
  String(value).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
