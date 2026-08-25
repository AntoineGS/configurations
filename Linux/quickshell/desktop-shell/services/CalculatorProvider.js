function isExpressionLike(query) {
  var value = String(query || "").trim()
  return /\d/.test(value)
    && (/[+*/^%=()-]/.test(value) || /\b(to|in)\b/i.test(value) || /\d\s*[a-zA-Z]+/.test(value))
}

function normalizeResult(stdout, maxLength) {
  var value = String(stdout || "")
  var limit = Number(maxLength || 0)
  if (!value || limit <= 0 || value.length > limit) return ""
  var firstLine = value.split(/\r?\n/)[0].trim()
  if (!firstLine || /^error\b/i.test(firstLine)) return ""
  return firstLine
}

function shouldAcceptResult(requestSerial, currentSerial, query, currentQuery) {
  return Number(requestSerial) === Number(currentSerial)
    && String(query || "") === String(currentQuery || "")
}

if (typeof module !== "undefined") {
  module.exports = {
    isExpressionLike: isExpressionLike,
    normalizeResult: normalizeResult,
    shouldAcceptResult: shouldAcceptResult
  }
}
