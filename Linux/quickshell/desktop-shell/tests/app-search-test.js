const assert = require("node:assert/strict")
const search = require("../services/AppSearch.js")

const apps = [
  { id: "org.gnome.Calculator", name: "Calculator", genericName: "Calculator", keywords: ["math"] },
  { id: "org.example.Contacts", name: "Contacts", genericName: "Address Book" },
  { id: "org.example.Hidden", name: "Hidden", noDisplay: true },
  { id: "com.brave.Browser", name: "Brave", comment: "Web browser", keywords: ["internet"] },
]

assert.deepEqual(search.sortedEntries(apps, "calc", () => false).map(row => row.entry.name), ["Calculator"])
assert.deepEqual(search.sortedEntries(apps, "internet", () => false).map(row => row.entry.name), ["Brave"])
assert.deepEqual(search.sortedEntries(apps, "calculator", () => false).map(row => row.entry.name), ["Calculator"])
assert.deepEqual(search.sortedEntries(apps, "", entry => entry.id === "com.brave.Browser").map(row => row.entry.name), ["Calculator", "Contacts"])
assert.equal(search.fuzzyScore(apps[1], "calculator"), -1)
