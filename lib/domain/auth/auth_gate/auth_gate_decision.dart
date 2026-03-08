/// Output of auth gate decision logic.
enum AuthGateDecision {
  loading,
  signedOut,
  needsProfile,
  ready,
  maintenance,
  forceUpgrade,
}

