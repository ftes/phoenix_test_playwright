{
  queryAll(root, selector) {
    return root.value === JSON.parse(selector) ? [root] : []
  }
}
