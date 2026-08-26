----------------------------- MODULE Unbounded -----------------------------
EXTENDS Naturals

VARIABLE value

\* This fixture must be rejected: Nat has no exact bounded Ada representation.
TypeOK == value \in Nat

HarnessInputType == [amount : 0..1]

HarnessOutcomeType == [accepted : BOOLEAN]

=============================================================================
