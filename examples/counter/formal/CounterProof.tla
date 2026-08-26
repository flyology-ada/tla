--------------------------- MODULE CounterProof ----------------------------
EXTENDS Naturals

VARIABLE count

\* This deliberately small proof module demonstrates the TLAPM side of the
\* workflow independently of TLC's bounded, trace-producing Counter module.
Init == count = 0

Increment == /\ count < 2
             /\ count' = count + 1

TypeOK == count \in Nat

THEOREM InitImpliesTypeOK == Init => TypeOK
\* Expanding the two definitions leaves a simple arithmetic obligation.
<1>. QED BY DEF Init, TypeOK

THEOREM IncrementPreservesTypeOK == TypeOK /\ Increment => TypeOK'
\* Priming TypeOK relates it to the post-transition value of count.
<1>. QED BY DEF Increment, TypeOK

=============================================================================
