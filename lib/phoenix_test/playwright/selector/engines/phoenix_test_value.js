{
  queryAll(root, selector) {
    const selectorWithoutQuotes = selector.substring(1, selector.length - 1)
    return root.value === selectorWithoutQuotes ? [root] : []
  }
}
