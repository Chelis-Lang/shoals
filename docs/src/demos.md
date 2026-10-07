# Counterexample examples

Bounded property search can find inputs that violate a financial model's stated
bound. These examples illustrate three mistakes and their corrections:

- `discount_le_one`: a wrong-sign linear discount can exceed one. Its control uses a rational discount for nonnegative rate and time.
- `variance_nonneg`: an Euler variance step can become negative. Its control floors the resulting variance at zero.
- `call_le_spot`: adding rather than subtracting the discounted strike term can price a call above spot. Its control uses subtraction.

A counterexample demonstrates an input that violates the stated bound. A
bounded search that finds no counterexample does not prove the property for
every possible input.

## Model-size examples

Numerical examples can compare a 200-step CRR call, a 60-period coupon bond,
and a 10,000-path Monte Carlo estimate with their formulas at selected
parameters. Monte Carlo results vary with the random seed and path count.
