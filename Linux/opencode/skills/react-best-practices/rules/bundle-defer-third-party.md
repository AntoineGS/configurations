---
title: Defer Non-Critical Third-Party Libraries
impact: MEDIUM
impactDescription: keeps them out of the main bundle
tags: bundle, third-party, analytics, defer
---

## Defer Non-Critical Third-Party Libraries

Analytics, logging, and error tracking don't block user interaction. Split them out of the main bundle and load them without holding up the first render.

**Incorrect (blocks initial bundle):**

```tsx
import { Analytics } from 'analytics-sdk/react'

export default function App() {
  return (
    <>
      <Routes />
      <Analytics />
    </>
  )
}
```

**Correct (loads in a separate chunk after the app renders):**

```tsx
import { lazy, Suspense } from 'react'

const Analytics = lazy(() =>
  import('analytics-sdk/react').then(m => ({ default: m.Analytics }))
)

export default function App() {
  return (
    <>
      <Routes />
      <Suspense fallback={null}>
        <Analytics />
      </Suspense>
    </>
  )
}
```
