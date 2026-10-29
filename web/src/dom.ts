export type Child = Node | string | number | false | null | undefined;

/** Create an element. Strings become text nodes, so a value from a graph file is never parsed as HTML. */
export function h<K extends keyof HTMLElementTagNameMap>(tag: K, attributes: Record<string, string> = {}, ...children: Child[]): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag);
  for (const [name, value] of Object.entries(attributes)) element.setAttribute(name, value);
  for (const child of children) {
    if (child == null || child === false) continue;
    element.append(typeof child === "object" ? child : document.createTextNode(String(child)));
  }
  return element;
}
