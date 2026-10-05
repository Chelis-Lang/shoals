<!-- BEGIN CHELIS MANAGED BLOCK: chelis-surface chelis@0.18.13 (sha256:13fd8ecdc638efcb) -->
# Chelis capability surface

This guide maps language operations, compiler support, and bundled `chelis-std`.
The numbered specs decide language behavior; code and executable tests establish
which parts the compiler implements. `chelis reef conform sync` copies this
guide into every shell's `docs/CHELIS_SURFACE.md`
([`spec/design/shell_repo_contract.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/design/shell_repo_contract.md) §3),
so a shell reads the guide of the release it pins.

This page describes the source tree it ships with: `main` in the compiler
repository, and the pinned release in a shell's copy. Relative paths and links
name files in [`Chelis-Lang/chelis`](https://github.com/Chelis-Lang/chelis).
Language rules, registered builtins, and target execution support have
separate owners, identified below.

If this guide disagrees with an owning source, correct the guide:

| Surface | Source of truth |
|---|---|
| Language operations and adjoints | [`spec/05-risc-primitives.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/05-risc-primitives.md), [`spec/06-transformations.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/06-transformations.md) |
| Syntax, types, dtypes and effects | [`spec/02-surf-syntax.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/02-surf-syntax.md), [`spec/04-type-system.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/04-type-system.md) |
| Builtin registration | `BUILTIN_NAMES` and `builtin_env`, `crates/chelis-types/src/builtins.rs` |
| IR and target implementation | `RiscOp`, `crates/chelis-ir/src/dag.rs`; `crates/chelis-compiler-api/src/compiler.rs`; `crates/chelis-backend-{c,hip,metal}` |
| Target contract | [`spec/08-backends.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/08-backends.md) and the dtype matrix in `spec/04` §1.1.3 |
| Command surface | `crates/chelis-cli/src/main.rs` and its CLI integration tests |
| Scope taxonomy (core vs std vs shell) | [`spec/design/chelis_canonical_reference.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/design/chelis_canonical_reference.md) §8.5 |

---

## 0. Checked programs, tensor DAGs, and host execution

Checking establishes types, effects, and ownership before target selection.
Lowering then keeps tensor work in a `RiscOp` DAG and represents functions,
collections, I/O, and other host work in a host execution program. One source
program can contain both. The host interpreter and generated host code call
tensor helpers admitted by the selected target (§6).

- **DAG:** `crates/chelis-ir/src/dag.rs`, `lower.rs`, and `tier2.rs` contain
  tensor nodes and derived-op lowerings. Eval and the C, HIP, and Metal emitters
  check capability separately by dtype, shape, and target.
- **Host execution:** `crates/chelis-ir/src/host.rs` represents calls, control,
  scalar and collection values, and tensor helpers. Eval uses
  `chelis-compiler-api/src/runtime/host_ops.rs`; compiled host programs use
  target host emitters and the carried runtime. Some builtin applications are
  explicitly eval/test-only (§3.5, §3.8, §3.9).

Transform rules include host values, lists, branches, and recursion;
implementation coverage is in §5. The prover's supported subset is in §12.
The checker's alias-resolved ADT information and authored signatures feed
host representation decisions.

**Lane legend used in the tables below:**

| Mark | Meaning |
|---|---|
| `DAG` | Has a tensor DAG lowering; target admission is described in §6. |
| `Host` | Uses a host execution form and its target's host-runtime support. |
| `DAG+Host` | Has both lowering paths; the selected entry and context decide which one is used. |

---

## 1. Tier-1 RISC primitives (the DAG)

These registered builtins have direct tensor DAG nodes. Their contracts come from
`spec/05` §2 and the dtype rules of `spec/04`. `D` denotes dimensions and `p`
a precision. Read-only tensor inputs are borrow-typed (`&tensor`) and are
auto-borrowed at ordinary call sites. An adjoint column describes float data
paths unless the named atom says otherwise. Scalar forms and target limits
are specified separately.

### 1.1 Elementwise binary — `spec/05` §2.1

| Name | Signature | AD adjoint (given upstream `g`) |
|---|---|---|
| `add` | `(&tensor[D,p], &tensor[D,p]) -> tensor[D,p]` | `(g, g)` |
| `sub` | `(&tensor[D,p], &tensor[D,p]) -> tensor[D,p]` | `(g, -g)` on floats; signed-integer forms are forward-only |
| `mul` | `(&tensor[D,p], &tensor[D,p]) -> tensor[D,p]` | `(g*y, g*x)` |
| `div` | `(&tensor[D,p_float], &tensor[D,p_float]) -> tensor[D,p_float]` | `(g/b, -g*y/b)`; IEEE-754, **float operands only** |
| `floor_div` | `(&tensor[D,p], &tensor[D,p]) -> tensor[D,p]` | **non-differentiable** — `grad` rejects; round quotient toward −∞ (Python `//`); ints and floats |
| `trunc_div` | `(&tensor[D,p_int], &tensor[D,p_int]) -> tensor[D,p_int]` | **non-differentiable** — `grad` rejects; round toward zero (C `/`); **integer operands only** |
| `max_elem` | `(&tensor[D,p], &tensor[D,p]) -> tensor[D,p]` | complete `g` to the exact operand selected by [05-OP-40], including its stored-bit tie rule; integer forms are forward-only |
| `min_elem` | `(&tensor[D,p], &tensor[D,p]) -> tensor[D,p]` | complete `g` to the exact operand selected by [05-OP-40], including its stored-bit tie rule; integer forms are forward-only |
| `cmplt` | `(&tensor[D,p], &tensor[D,p]) -> tensor[D,bool]` | zero gradient (by design) |

`div` and `recip` follow IEEE-754 float division, including signed zero and
infinity. `/` desugars to
`div`, so integer `/` is a type error. Use `floor_div` for a quotient rounded
toward −∞, `trunc_div` for an integer quotient rounded toward zero, or
explicitly cast before float division. Integer overflow is checked unless a
separately named modular operation applies (`spec/04` [04-NUM-3/7]).

### 1.2 Elementwise unary — `spec/05` §2.2

| Name | AD adjoint |
|---|---|
| `neg` | `-g` for floats; integer forward execution is checked |
| `recip` | `-g*y*y` (= `-g/x²`) |
| `exp` | `g*exp(x)` |
| `log` | `g/x` |
| `sin` | `g*cos(x)` |
| `cos` | `-g*sin(x)` |
| `tan` | `g/cos²(x)` |
| `atan` | `g/(1+x²)` |
| `erf` | `g*(2/sqrt(pi))*exp(-x²)` |
| `erfc` | `-g*(2/sqrt(pi))*exp(-x²)` |
| `sqrt` | `g/(2*sqrt(x))` |
| `abs` | `g*sign(x)` (0 at x=0) for floats; integer form is forward-only |
| `floor` | float path: `grad` rejects (`PiecewiseConstant`); integer form is identity |
| `ceil` | float path: `grad` rejects (`PiecewiseConstant`); integer form is identity |
| `round` | ties to even; float path: `grad` rejects (`PiecewiseConstant`); integer form is identity |

`recip`, transcendental functions, and `sqrt` admit floats. `neg`, `abs`,
`floor`, `ceil`, and `round` also admit signed integers under the rules above.

### 1.3 Reduction — `spec/05` §2.3

| Name | Signature | AD adjoint |
|---|---|---|
| `sum` | `(&tensor[D,p], axes: Axis+, accumulator: prec = default(p)) -> tensor[D\K,sum_result(p,accumulator)]` | expand `g` across each removed axis at operand precision |
| `count` | `(&tensor[D,bool], axes: Axis+) -> tensor[D\K,i64]` | **non-differentiable** (`IntegerReductionOutput`) |
| `max_reduce` | `(&tensor[D,p], axes: Axis+) -> tensor[D\K,p]` | split `g` among equal extrema; first NaN receives all of `g` |
| `min_reduce` | `(&tensor[D,p], axes: Axis+) -> tensor[D\K,p]` | split `g` among equal extrema; first NaN receives all of `g` |
| `prod_reduce` | `(&tensor[D,p], axes: Axis+) -> tensor[D\K,p]` | reverse the exact balanced multiplication tree, including zeros |
| `argmax_reduce` | `(&tensor[..,p], axis: i32) -> tensor[..,i64]` | **non-differentiable** (index output) |
| `argmin_reduce` | `(&tensor[..,p], axis: i32) -> tensor[..,i64]` | **non-differentiable** (index output) |

`Axis+` is one or more unique statically resolved positional `i32` axes or
named axes. Positional negative axes count from the end. Concrete-rank
multi-axis reductions accept positional axes; rank-polymorphic forms use
named axes. Runtime axis expressions and mixed or duplicate selections
are type errors. The checker applies these rules before a backend is chosen.

`sum` and `prod_reduce` use the specified balanced trees, with integer
overflow checked at each operation. `count` has one dedicated node with
normalized original positions in descending order. For `sum`, the default
`bf16`/`f16` accumulator is `f32`, and the result returns to `bf16`/`f16`.
Other defaults are
`f32→f32`, `f64→f64`, `i8/i16→i32`, `i32→i32`, and `i64→i64`.
`sum`, `cumsum`, `trace`, and `einsum` all return
`sum_result(p, default(p))`, so over `i8` or `i16` each returns `i32`: a
total of N values needs more bits than its elements, so the stored tensor
keeps its dtype and only the aggregate widens. Declare the result as `i32`,
pass `accumulator=i64` to `sum` or `einsum`, or narrow it with an explicit
`cast`.
An explicit wider accumulator, written as the final argument
`accumulator=<dtype>` (`sum(x, 0i32, accumulator=f64)`), follows the exact
result matrix in `spec/04` §5.7.1. `mean` is a float-only derived reduction (§2) with no
accumulator parameter.

### 1.4 Windowed reduction — `spec/05` §2.3.1 (Valid padding only)

| Name | Signature |
|---|---|
| `reduce_window_max` / `_min` / `_sum` / `_mean` | `(&tensor[..,p], window_shape: List[i64], strides: List[i64]) -> tensor[..,p]` |

This family lowers to `RiscOp::ReduceWindow` with a reducer kind and uses
`ReduceWindowGrad` for its adjoint. With valid padding, output extent is
`floor((d - window)/stride) + 1`; explicit `pad` supplies other boundaries.
The C target has a guarded windowed path. HIP and Metal reject this node;
see §6 for dtype and dynamic-extent restrictions.

### 1.5 Movement — `spec/05` §2.4

| Name | Signature | AD adjoint |
|---|---|---|
| `reshape` | `(&tensor[D_old,p], shape) -> tensor[D_new,p]` | `reshape(g, old_shape)` |
| `permute` | `(&tensor[..,p], axes: i32...) -> tensor[..,p]` | `permute(g, inverse_axes)` |
| `expand` | `(&tensor[D,p], axis: i32, size: i64) -> tensor[D',p]` | `insert(sum(g, axis), axis, 1i64)` |
| `insert` | `(&tensor[D,p], axis: i32, size: i64) -> tensor[D_plus,p]` | `sum(g, axis)` |
| `pad` | `(&tensor[D,p], padding, fill) -> tensor[D',p]` | `shrink(g, inverse_padding)` |
| `shrink` | `(&tensor[D,p], bounds) -> tensor[D',p]` | `pad(g, inverse_bounds)` |
| `stride` | `(&tensor[D,p], strides) -> tensor[D',p]` | [05-MOV-1]'s zero-filled inverse sampling map at the original shape |

`expand` sets an existing size-1 axis to `size` and leaves the rank alone; `insert`
adds an axis and raises the rank by one. Neither copies data (stride-0 on the
broadcast axis). Axes for `expand` and `insert` are statically resolved;
the spec also admits named-axis forms. Their size/bound values have
separate runtime-extent rules (`spec/04` §4.7 and `spec/05` §2.4).
Target support for node-valued bounds is narrower than the language rule.

### 1.6 Memory & effectful — `spec/05` §2.5–2.6

| Name | Signature | AD / effect |
|---|---|---|
| `const` | `(value, shape...) -> tensor[shape,p]` | zero gradient |
| `load` | `(source, shape...) -> tensor[shape,p]` | zero gradient |
| `dropout` | `(key, &tensor[D,p_float], rate: p_float) -> tensor[D,p_float]` | consumes its key; fixed-control data adjoint replays the forward mask. Eval and selected C builds admit runtime key/rate; device draws are rejected (§6). |
| `uniform_like` | `(key, &tensor[D,p_float], lo: p_float, hi: p_float) -> tensor[D,p_float]` | active float `p`; consumes its key and introduces no effect; zero gradient to the template |
| `key_from_seed` | `(i64) -> key` | [05-OP-69]; non-differentiable |
| `split_key` | `(key) -> (key, key)` | [05-OP-70]; consumes its key ([04-LIN-9]) |
| `split_keys` | `(key, i64) -> tensor[n, key]` | [05-OP-71]; consumes its key; `n` is the runtime count |
| `fold_in` | `(key, i64) -> key` | [05-OP-72]; consumes its key |

`const` and `load` are lowering-created memory nodes. Other IR nodes, including `Store`, `Copy`, `Realize`, `Cast`, `FusedElem`,
`OneHot`, and `BlasMatmul`, are internal representations or come from
separate language forms. Random keys are affine values. A draw consumes its
key without introducing `IO`; the exact mask, rate validation, and pathwise
adjoint are governed by [05-OP-37]. C entry support is described in §6.

### 1.7 Sparse tensor-lane nodes — `spec/05` §3.5

The sparse builtins below have distinct DAG identities. Eval and C implement
them; HIP admits a narrower payload/index/source subset and Metal rejects
the sparse nodes (§6).

| Surf builtin | Lowers to | Signature | AD adjoint |
|---|---|---|---|
| `gather` | `RiscOp::Gather{axis}` | `(&values, &indices, axis: i32) -> tensor` | `ScatterAdd` |
| `scatter_replace` | `RiscOp::Scatter{axis}` | `(&base, &indices, &updates, axis: i32) -> tensor` | **no_grad** (`NonDeterministicAtDuplicateIndices`) |
| `scatter_elements` | `RiscOp::ScatterElements{axis}` | `(&data, &indices, &updates, axis: i32) -> tensor` | **no_grad** (`NonDeterministicAtDuplicateIndices`) |
| _(scatter-add internal)_ | `RiscOp::ScatterAdd{axis}` | — | `Gather` |

`scatter_replace` uses a deterministic last-write-wins row-major rule for
duplicate indices. `scatter_elements` is the elementwise variant
(`indices.shape == updates.shape`, `output.shape == data.shape`,
`spec/05` §3.5.1), with the same duplicate policy and AD rejection.
The five-argument, string-mode `scatter` is a separate host-runtime form (§3).

---

## 2. Derived builtins and tensor compositions

`spec/05` §3–4 gives these names typed identities and lowering rules. Most
are implemented by compositions of primitive nodes in
`crates/chelis-ir/src/tier2.rs`. `relu` has a dedicated DAG node and
its own zero rule.

| Name | Lowering | AD |
|---|---|---|
| `eq`,`neq`,`gt`,`gte`,`lte`,`lt` | exact comparison identities; direct `Compare` nodes exist alongside the specified compositions | bool result has zero cotangent |
| `and`,`or`,`not` | bool-only operations ([05-OP-26..28]); direct `Logical` nodes exist | structural `grad` rejection |
| `relu` | dedicated `RiscOp::Relu`; forward equals stored-bit `max_elem(x, 0)` | `g` only where `0 < x`; exact +0 at both zeros and NaN |
| `sigmoid` | `recip(add(1, exp(neg(x))))` | differentiable |
| `tanh`,`silu`,`gelu`,`gelu_tanh`,`standard_normal_cdf` | `tier2.rs` decompositions; `standard_normal_cdf` is the standard normal CDF `Phi` over `erfc`, `gelu` is exact (`x*Phi(x)`), `gelu_tanh` the tanh approximation | differentiable |
| `matmul` | `expand`+`mul`+`sum`, pattern-matched to BLAS (`spec/05` §4.1); optional `accumulator` | differentiable |
| `mean` | float-only `sum` followed by division by the selected axis extent, in canonical multi-axis order | differentiable |
| `softmax` | max-shift + `exp` + `sum` + `div` (`spec/05` §4.2) | differentiable |
| `layer_norm` | explicit epsilon plus mean/var normalize + affine (`spec/05` §4.4) | differentiable |
| `conv` | N-dimensional padded window gather → one matrix contraction → reshape/permute; explicit per-axis i64 strides and `(low,high)` padding pairs (`spec/05` §4.5) | differentiable |

Some derived arithmetic also has a compiled-host path when a surrounding
function is represented in the host program. Target admission is checked
separately.

Composite recipes such as `linear`,
`cross_entropy`, `embedding`, `multi_head_attention`, and `argmax`
(`spec/05` §3.5, §4.3–4.7) are library compositions. Use an imported definition or
compose the underlying operations explicitly.

The [`explicit_normalization.ch`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/examples/explicit_normalization.ch)
example defines `normalize` as an ordinary function.

---

## 3. Host-runtime and other non-primitive builtins

Most operations here have a host execution form, evaluated by
`host_ops.rs` or emitted through target host code and `chelis_*` runtime
calls. Some also acquire a direct tensor DAG form in a tensor context:
`where`, comparison/logical operations, integer bitwise operations, and
selected tensor helpers are examples. Section 4 lists builtin names;
lowering and target support depend on the operation and selected entry
(§6). Host AD is
implemented for selected paths, with wider semantics specified by
`spec/06` (§5).

### 3.1 Data-dependent and tensor construction operations — `spec/05` §1, §3

| Name | Signature | Notes |
|---|---|---|
| `cumsum` | `(&tensor, axis: i32) -> tensor` | cumulative sum along axis; result uses `sum_result(p, default(p))`, so narrow-integer output can widen |
| `sort` | `(&tensor, axis: i32) -> (values, indices)` | stable ordering; returns values and an `i64` index tensor |
| `einsum` | `(equation: string, &lhs, &rhs) -> tensor` | the implemented equation subset is two-operand and excludes ellipsis; static contradictions reject at checking |
| `diagonal` | `(&tensor, axis1: i32, axis2: i32) -> tensor` | diagonal extraction |
| `trace` | `(&tensor, axis1: i32, axis2: i32) -> tensor` | matrix trace |
| `where` | `(&cond, &a, &b) -> tensor` | bool selection has a direct `RiscOp::Where` form; compiled Metal rejects that direct node |
| `clamp` | `(&tensor, lo, hi) -> tensor` | elementwise clip |
| `concat` | `(tensors: List[tensor], axis: i32) -> tensor` | join tensors along axis; ordinary two-list concatenation has no axis slot |
| `split` | `(&tensor, axis: i32, sizes: List[int]) -> list` | partition along axis |
| `scatter` | `(base, indices, updates, axis: i32, mode: string) -> tensor` | registered host form; its string mode conflicts with the public [05-OP-33] contract |
| `pad_sequences`, `pad_sequences_to` | typed List input, pad value, and optional width | runtime-derived extents; [05-OP-9..10] govern all-dtype padding and adjoints |

### 3.2 Host-runtime tensor builder — `spec/05` §3.6

| Name | Signature | Notes |
|---|---|---|
| `tensor_scan` | `(initial: T, fn: (T,i64)->T ! E, n: i64) -> tensor[n,..state_shape(T),element(T)] ! E` | [05-HOST-1] and [05-OP-38] define scalar or fixed-shape tensor state, ordered callback effects, and typed output. Eval and compiled C run scalar and tensor states; transform coverage is incomplete. |

`tensor_scan` stacks successive states into a tensor; list `scan` (§3.3)
returns a `List`. Its spec includes float-state AD and `vmap` rules.
Compiled C runs it as the list `scan` over `range(0, n)` stacked at the
state's own dtype; a tensor state stacks against the initial state, so
`n = 0` keeps every state extent.

### 3.3 Higher-order list / sequence combinators

`map`, `filter`, `fold`, `scan`, `partition`, `flat_map`, `flatten`, `zip`,
`enumerate`, `chunk`, `take`, `skip`, `range`, `append`, `index`, `len`,
and the List overload of `concat`. Higher-order forms accept callable values
and execute eagerly in list order. `len` and `index` auto-borrow a List or
Dict query argument; they do not consume that container (`spec/05` §1.3.1).
At each function entry, tensors in a `List[tensor[n, p]]` parameter
contribute to the named extent `n` check; `List[tensor[2, p]]` checks the
literal extent of each element. This includes nested Lists, internal calls,
and retained callable invocations. An empty List contributes no named witness.
Eval and C enforce these checks before the function body; see
[`list_shared_extent.ch`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/examples/list_shared_extent.ch).
The spec defines positional List cotangents for several forms. Eval/C tests
cover selected list gradients, including
`to_list`/`map`/`to_tensor` paths; other transforms and callback shapes
may reject (`crates/chelis-cli/tests/ad_host_list_combinators.rs`). The C
build rejects a direct named List gradient when the List actual selected for
differentiation is local and its recursive shape cannot be reconstructed;
Eval handles the form. See [#2740](https://github.com/Chelis-Lang/chelis/issues/2740).

### 3.4 Collections, strings, conversions

- **Dict:** `dict_of`, `dict_get`, `dict_contains`, `dict_remove`, `dict_insert`,
  `dict_merge`, `dict_keys`, `dict_values`, `dict_entries`.
- **String:** `char_code`, `char_from_code`, `string_len`, `string_concat`,
  `string_slice`, `string_contains`, `string_starts_with`, `string_ends_with`,
  `string_trim`, `to_string`.
- **Scalar coercion:** `to_int`, `to_float`.
- **Tensor↔host bridges & queries:** `rank`, `shape`, `numel`, `tensor_to_scalar`,
  `scalar_to_tensor`, `to_tensor`, `to_list`. `shape(t, axis: i32)` returns the
  selected runtime extent as `i64`; reductions/expands still need
  compile-time-constant axes regardless.

### 3.5 I/O and process — introduces `IO`

`read_file`, `write_file`, `read_lines`, `read_bytes`, `file_exists`, `list_dir`,
`mmap_file`, `mmap_read`, `mmap_len`, `process_run`, `clock_wall_read`,
`clock_monotonic_read`.

| Name | Signature | Notes |
|---|---|---|
| `list_dir` | `string -> List[string]` | Entry names, not paths. Ordered by host-name bytes; strict UTF-8 conversion under [05-HOST-4]. An invalid name traps `IO` for the complete call. |
| `process_run` | `(cmd: string, args: List[string]) -> (i64, string, string)` | argv, no shell. Eval and compiled C run it; a signal reports `-1`, and a capture that is not UTF-8 traps `IO`. |
| `clock_wall_read` | `() -> (i64, i64)` | Host wall clock on the POSIX timescale as `(seconds, nanoseconds)` since 1970-01-01T00:00:00 UTC, from one reading; nanoseconds in `[0, 10^9)`. Eval and compiled C run it. [05-OP-75] |
| `clock_monotonic_read` | `() -> (i64, i64)` | A clock that never runs backwards, as `(seconds, nanoseconds)` from an unspecified origin. Eval and compiled C run it. [05-OP-75] |

String-valued path APIs cannot directly name non-UTF-8 files. `list_dir`
preserves valid names exactly, without normalization; on conversion failure its
diagnostic identifies the directory and first invalid entry in host-name order
using reversible byte escapes. A byte-preserving path API is not provided by
this contract.

The executable [directory listing example](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/examples/io/list_directory.ch)
prints names in that order. The fixture-based eval/C integration test is
`crates/chelis-cli/tests/issue_1479_list_dir_lane_parity.rs`.

### 3.6 Diagnostics & test — `Test` effect on asserts

`print`, `fail`, `debug`, and the `test_assert*` family: `test_assert`,
`test_assert_eq`, `test_assert_close_tensor`, `test_assert_eq_tensor`.

### 3.7 Integer and bitwise elementwise

`mod`, `bitand`, `bitor`, `bitxor`, `shl`, `shr` operate on integer scalars
or same-shaped integer tensors, and `mod` also on floats, where it is C
`fmod` ([05-OP-64]). They have direct DAG forms (`RiscOp::Mod` and
`RiscOp::Bitwise`). Eval and
compiled C execute bitwise work at the declared width, including integer
expressions used as runtime extents. `grad` retains discrete expressions
that are fixed coefficients and rejects a selected discrete path; `vmap`
maps admitted bitwise work elementwise. HIP has direct typed tensor kernels and
Metal has direct rank-one tensor kernels for all four signed widths. Metal rejects activated shifts
until it can gate their checks. Shifts use declared-width
two's-complement semantics; counts at or above the width fully shift out
the value, while negative counts trap ([04-NUM-13]).

### 3.8 Decimal rounding

`round_to(x: f64|f32|f16|bf16, places: int) -> same dtype` rounds the
operand's exact binary value to the nearest multiple of `10^(-places)`,
ties to the even coefficient, and finalizes once at the operand's own width
([05-OP-1], [04-NUM-8]). `places` is any signed integer: a negative count
rounds left of the decimal point, a count finer than the value is the
identity, a zero result keeps the operand's sign, and a result past the
largest finite value is the signed infinity. Non-finite operands pass
through unchanged. Eval and compiled C share one definition.
Eval/test execute it; compiled builds reject it through the shared
eval-only gate. [05-HOST-2] requires compiled-host support.

The source-defined `Std.Io.Json` module (§11) provides JSON values with
distinct `JsonInt`, `JsonBigInt`, and `JsonFloat` numeric variants.

### 3.9 CSV I/O

The builtin CSV carrier is exactly `List[Dict[string,string]]`: the input's
first record supplies the column names, the carrier contains only data rows,
and parsing keeps every cell as text. Numeric meaning enters only through an
explicit `csv_int*` or `csv_f64*` accessor ([05-OP-2..3]).
Every operation validates the carrier and fails loudly; no cell is silently
coerced or defaulted. Eval and compiled C share one definition of every
operation. The separate source-defined module is `Std.Io.Csv` (§11).

| Name | Signature | Notes |
|---|---|---|
| `parse_csv` | `(s: string) -> List[Dict[string,string]]` | RFC-4180-style quoted fields, doubled quotes, embedded commas/newlines, LF or CRLF, leading UTF-8 BOM; rejects malformed, ragged, blank-interior, or duplicate-header input |
| `to_csv` | `(rows: List[Dict[string,string]]) -> string` | requires every row to have the first row's unique string-keyed columns; quotes fields as needed and emits LF rows with a trailing newline |
| `csv_f64s` | `(rows, col: string) -> List[f64]` | strict finite JSON-number grammar after ASCII space/tab trim; overflow and non-numbers fail |
| `csv_ints` | `(rows, col: string) -> List[i64]` | exact integer grammar and i64 range; float syntax fails naming `csv_f64s` |
| `csv_strs` | `(rows, col: string) -> List[string]` | whole column verbatim |
| `csv_nrows` | `(rows) -> i64` | exact data-row count |
| `csv_cols` | `(rows) -> List[string]` | first row's columns in insertion order |
| `csv_f64` | `(rows, row: int, col: string) -> f64` | one cell; row is a nonnegative 0-based data-row index |
| `csv_int` | `(rows, row: int, col: string) -> i64` | one exact integer cell |
| `csv_str` | `(rows, row: int, col: string) -> string` | one cell verbatim |

Missing columns name the requested column and list the available columns.
The shared eval-only gate in `crates/chelis-ir/src/host.rs` rejects these
builtins in compiled builds, including calls reached through a helper.
The source-defined `Std.Io.Csv` module supplies the compiled-host path
(§11). Builtin compiled-host support required by [05-HOST-2] is tracked
by chelis#1297.

---

## 4. Complete closed vocabulary (completeness check)

Every name in `BUILTIN_NAMES` (`crates/chelis-types/src/builtins.rs`), verbatim. The
fenced block below mirrors the array exactly and is locked to it by the
`doc_surface_section_4_mirrors_builtin_names` test (`crates/chelis-types/src/builtins.rs`),
so it cannot silently drift. Its group labels reflect the vocabulary
organization. Target and AD support are described in their own sections.
To change the array, review
the owning spec, registration, and this exact list together.

Two capabilities live *outside* the array and are intentionally absent below: `const`
and `load` are `RiscOp` memory nodes produced during lowering. Both are documented in
§1.6. Keywords and special forms include `cast`, `cast_trunc`,
`cast_saturate`, `cast_wrap`, `copy`, `grad`, `vmap`, `jit`, and `realize`.

```
Tier-1 DAG:   add sub mul div floor_div trunc_div max_elem min_elem cmplt neg recip exp log sin cos tan atan erf erfc sqrt
              abs floor ceil round sum count max_reduce min_reduce prod_reduce argmax_reduce
              argmin_reduce reduce_window_max reduce_window_min reduce_window_sum
              reduce_window_mean reshape permute expand insert pad shrink stride
              uniform_like dropout gather scatter_replace scatter_elements
              key_from_seed split_key split_keys fold_in
Tier-2 DAG:   eq neq lt gt lte gte and or not relu sigmoid tanh silu gelu gelu_tanh
              standard_normal_cdf
              softmax mean matmul layer_norm conv
Host lane:    cumsum sort einsum diagonal trace where clamp concat split scatter
              pad_sequences pad_sequences_to tensor_scan
              map filter fold scan partition flat_map flatten zip enumerate chunk
              take skip range append index len
              dict_of dict_get dict_contains dict_remove dict_insert dict_merge
              dict_keys dict_values dict_entries
              char_code char_from_code string_len string_concat string_slice string_contains
              string_starts_with string_ends_with string_trim to_string to_int
              to_float rank shape numel tensor_to_scalar scalar_to_tensor to_tensor
              to_list
              read_file write_file read_lines read_bytes file_exists list_dir
              mmap_file mmap_read mmap_len process_run
              clock_wall_read clock_monotonic_read
              round_to
              parse_csv to_csv csv_f64s csv_ints csv_strs csv_nrows csv_cols
              csv_f64 csv_int csv_str
              print fail debug test_assert test_assert_eq test_assert_close_tensor
              test_assert_eq_tensor
              mod bitand bitor bitxor shl shr
              drop
```

Prelude ADTs/constructors (also in scope): `Option`/`Some`/`None`,
`List`/`Cons`/`Nil`, and `MappedFile`.

---

## 5. Autodiff: specified rules and implemented paths

`grad` is a compiler transform. `spec/06` §2 and the [05-OP-N] atoms
determine an operation's adjoint, zero cotangent, or structural rejection.
Each target checks whether it can lower the selected source function.

- **Float tensor paths:** `add`, `sub`, `mul`, `div`, supported unary functions,
  reductions, movement, `matmul`, derived activations, `relu`, and `gather`
  have specified adjoints. `max_elem`/`min_elem` use [05-OP-40]'s exact
  selection; `relu` uses its distinct [05-OP-43] zero rule. `prod_reduce`
  differentiates its balanced tree. A target may reject the resulting
  backward DAG.
- **Zero cotangent or barrier:** `cmplt` and comparison results, `const`,
  `load`, and the `uniform_like` template carry zero cotangent.
  `stop_gradient` cuts a selected path. Logical operations reject `grad`
  structurally.
- **Structural rejection:** float `floor`/`ceil`/`round` and the named
  casts `cast_trunc`, `cast_saturate` and `cast_wrap` are piecewise constant; `count` and argument reductions have discrete
  outputs; replace-scatter variants reject duplicate-sensitive gradients.
  Integer arithmetic is forward-only where its atom says so.
- **Host values and control:** `spec/06` §2.10 defines cotangents for
  selected `List` combinators, the executed `if`/`match` branch, recursive
  trajectories, and ADT fields. Integration tests cover
  Eval list `map`/round-trip gradients and selected compiled List,
  scalar, and ADT paths (`ad_host_list_combinators.rs`,
  `issue_620_static_if_adt_grad.rs`). Other shapes can fail at transform
  lowering or at a target ABI; `tensor_scan` is one such incomplete builder.

For a composed gradient, use a scalar result and check the exact execution
mode. A non-scalar result needs an explicit seed under `spec/06` §8.3.
`grad(f, wrt=x)` returns one selected gradient directly; multiple selected
parameters return a tuple in authored selector order. A discrete field of
a recursive parameter has `unit` cotangent.
[`spec/design/differentiable_language.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/design/differentiable_language.md)
tracks implementation sequencing, while `spec/06` owns the language rule.

---

## 6. Backends — `spec/08-backends.md`

`chelis build` selects C, HIP, or Metal and invokes the native toolchain to
produce an executable for observable programs or a static library for
modules of callable definitions. It retains generated source, headers,
and carried runtime artifacts. `--emit-c` stops after source emission and
runtime staging, prints compile guidance, and requires no native compiler
or archiver. Host compilation disables implicit floating-point contraction.
CPU is the primary acceptance lane; HIP and Metal are prerelease targets
with known imperfections. Generated host code can carry selected tensor
helpers, while device kernels have their own supported operation sets.
`spec/04` §1.1.3 controls dtype admission and `spec/08` controls target
strategy; rejection gates are in
`chelis-compiler-api/src/compiler.rs`.

Build checks type, effect, and linearity over its selected source or linked
Reef target before removing unreachable definitions for emission. A dormant
semantic error in selected code fails the build; files outside that target do
not enter the check. Well-typed unreachable eval-only definitions can still be
removed before the retained program reaches backend capability checks.

| Target | Emits | Status |
|---|---|---|
| `c` (default) | C source, header, carried runtime and flags; OpenMP and BLAS paths where selected | broad host and tensor path with explicit feature gates |
| `hip` | C++ host source with embedded HIP kernel strings, runtime, and rocBLAS matmul path | selected GPU nodes and host wrappers; capability gates apply before emission |
| `metal` | Objective-C++ host source with embedded MSL kernel strings and runtime | selected GPU nodes and host wrappers; dtype and operation gates apply |

### 6.1 Host wrappers and device routing

HIP and Metal both emit host programs. Host wrappers invoke compiled tensor
helpers according to the target and selected entry
(`crates/chelis-cli/src/main.rs`). Before emission, the compiler checks
effects, eval-only builtins, and helper DAG capabilities. HIP admits
literal-bound `pad`/`shrink` DAG nodes but rejects their C-host helper
route; count helpers also receive device capability checks.

### 6.2 DAG-lane GPU coverage gaps

| Op / feature | C | HIP | Metal |
|---|---|---|---|
| Ordinary supported elementwise and reductions | available by operation | device subset; exact reduction cells have gates | device subset; exact reduction cells have gates |
| Direct `Compare`, `Logical`, `Where` | admitted | admitted | rejected pending exact kernels |
| Direct `Sub`, `MaxElem`, `MinElem` and extrema adjoints | admitted | admitted with target dtype limits | rejected pending exact kernels |
| `BlasMatmul` | BLAS/host path | rocBLAS, including selected f16/bf16 paths | tiled MSL path |
| `ReduceWindow` / `ReduceWindowGrad` | guarded C path | rejected | rejected |
| `Pad`, `Shrink` | admitted, including supported runtime bounds | literal-bound direct DAG admitted; node-valued bounds and inexact host-helper routing rejected | target-specific bounds and direct-op gates apply |
| Runtime `shape` value reads / node-valued movement | admitted where the C entry can carry them | device reads and node-valued bounds rejected | device reads and node-valued bounds rejected |
| `dropout` | selected C entries admit runtime key and rate | draws rejected | draws rejected |
| Sparse `Gather`/scatter nodes | admitted by exact operation | f32 payload and restricted index/source forms | rejected |
| `f64` tensor work | admitted | admitted on supported operations | hard-rejected ([04-TGT-1]) |
| f16/bf16 tensor work | admitted by operation | operation-limited (`spec/04` §1.1.3) | f16 admitted; bf16 requires Apple7+ |

The exact `spec/04` table and target gates decide each operation and dtype
cell. Unsupported operations produce target diagnostics before emission.

### 6.3 Exact eval/C output gate

`chelis lane-check <FILE|DIRECTORY> [--json] [--timeout SECONDS]` evaluates
each `.ch` program, builds C, compiles and links its carried runtime with
strict `-O2 -ffp-contract=off -fno-fast-math` flags, runs the binary, and
compares complete UTF-8 stdout through the shared exact comparator.
Directory entries are visited in sorted relative-path order without following
symlinks. No float tolerance or automatic skip applies; unsupported C,
library-only/zero-output programs, and an empty corpus are errors.
Exit 0 requires at least one comparison and no errors or divergences;
divergences exit 1 and infrastructure/unsupported/timeout errors exit 2.
`--json` writes one versioned NDJSON record per program followed by a
summary with a `proof_scope`. Human-readable diagnostics are the default.

Local invocations report an `unpinned-host` scope for diagnosis, **not**
hermetic acceptance. The authoritative x86-64 Linux gate is
`nix build .#checks.x86_64-linux.lane-check`; inspect its
`report.ndjson` output. The check owns the locked Chelis/compiler/native
closure, an exact-safe int/bool/dyadic-float corpus (including signed zero),
the sanitized runtime environment, and a queried-compiler-target check.
It is not available as a Darwin check, and its passing verdict does not
generalize to another hardware tuple. See
[`manual_gates.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/docs/manual_gates.md#compiler-feature-acceptance-gates).

An existing or substituted Nix output is a receipt from its recorded builder,
not evidence that the current host ran the gate. To repeat on the current
Linux builder, first build the check, then use
`nix build --rebuild --no-substitute .#checks.x86_64-linux.lane-check`;
Nix compares the fresh report against the existing output.

---

## 7. Types, shapes, and ownership — `spec/04-type-system.md`

- **Primitive types:** four floats (`f16`, `bf16`, `f32`, `f64`), four
  signed integers (`i8`, `i16`, `i32`, `i64`), `bool`, `key`, and
  `string`. `unit` is a separate type. `f8e4m3` and the `uint*`
  spellings are reserved and rejected. Each target's admitted numeric cells are in `spec/04`
  §1.1.3; a language-level dtype is not automatically a device dtype.
- **Literals and conversion:** unsuffixed integers default to `i32`
  and floats to `f32`. There is no implicit precision promotion.
  `cast(x, T)` is checked ([04-NUM-14]); a fractional or non-finite
  float cannot be silently converted to an integer. The named lossy
  casts each state their loss: `cast_trunc(x, T)` truncates a float
  toward zero with `Domain`/`Overflow` traps ([05-OP-6]);
  `cast_saturate(x, T)` truncates a float and clamps it, or clamps a
  signed integer, to the integer target, trapping `Domain` only on NaN
  ([05-OP-23]); `cast_wrap(x, T)` keeps the target-width two's
  complement value of a signed integer and never traps ([05-OP-24]).
  `spec/04` [04-NUM-15] fixes the first offending element of a tensor
  cast by lowest row-major flat index. HIP currently rejects the compiled
  named casts until their device traps are implemented.
- **Dimensions:** named axes agree by name, with symbolic extents
  for runtime-varying sizes and concrete extents for fixed sizes.
  Wildcard `*` and rank binders `..r` have restricted contexts
  (`spec/04` §4.5). Ordinary binary tensor operators never broadcast;
  use explicit `expand` or movement. A runtime `shape(t, axis)` query
  can return an `i64` extent, while an axis that selects a reduction
  or `expand` dimension resolves statically.
- **Ownership:** owned tensor and key values have linear-use rules.
  Read-only primitive tensor arguments auto-borrow; `len`/`index`
  auto-borrow their List/Dict query argument. `copy()` makes an
  explicit owned copy; `realize` and `drop` consume. Key operations
  consume their key. The ownership pass carries borrow, move, clone,
  and drop obligations into verified lowering.
- **Generic bounds:** a binder may declare `Float`, `Int`, or
  `Numeric` ([04-DTYPE-2]); `Numeric` excludes `bool`. Bounds survive
  aliases, imports, and higher-order uses. The exported stdlib signatures declare
  applicable dtype families in `packages/chelis-std/src/`.

`spec/04` §5.7.1 gives reduction result dtypes and accumulator choices.
The checker rejects unsupported generic bodies and ambiguous dimensions
before target selection.

---

## 8. Effects — `crates/chelis-effects`

| Effect | Introduced by | Handled by |
|---|---|---|
| `IO` | file ops, `mmap_*`, `process_run`, `clock_*_read`, `print` | checked execution boundary / runtime |
| `Test` | `test_assert*` | test/root boundary |
| `Accum` | internal gradient accumulation | compiler-internal |
| `Resource(Device)` | `with device(...)` placement region | checked handler and selected target |

Effects are inferred and checked with types before lowering; `chelis check`
reports effect rows. `dropout` and `uniform_like` take and consume explicit
`key` arguments.

Resource regions are checked against the chosen target before an artifact
is exposed. C host emission recognizes the exact `cpu` selector
and rejects other designators with `BuildTargetMismatch`. Entry-scoped
compilation validates its selected dependency closure, while whole-program
emission covers all definitions. Contextual compilation rejects an imported
callable if its host representation cannot carry it.

---

## 9. Transformations — `spec/06-transformations.md`

These are language forms and compiler transforms, not stdlib functions:

| Transform | Semantics |
|---|---|
| `grad` | Reverse-mode AD; `wrt` selects parameters. One selected target returns its gradient directly; several return an ordered tuple. See §5. |
| `vmap` | Map a function over a batch axis; mapped tensor and key forms, shared arguments, and runtime-extent restrictions are in `spec/06` §3. |
| `jit` | Compilation and cache hint that preserves the function's language semantics (`spec/06` §4); target execution requires a supported lowering. |
| `realize` | Force materialization of a (lazy) tensor; a consuming operation. |

Transform composition is governed by `spec/06`, including
`vmap(grad(f))` for per-example gradients. Transform preparation
rejects a body that reaches an unsupported host-only builder such as
`tensor_scan` at the transform boundary. A successful transform check does
not replace the selected backend's admission check.

---

## 10. `chelis` CLI surface — `crates/chelis-cli`

| Command | Purpose | Style gate? |
|---|---|---|
| `build` | Emit C/HIP/Metal source (`--target {c\|hip\|metal}`, default `c`) and carried runtime artifacts; `.dp` inputs use Deep ingestion | yes |
| `check` | Type/effect/linearity front-end (`--show-inferred`) | yes |
| `validate` | Syntax validation (`--surf`/`--deep`/`--desugar`) | yes for file input |
| `eval` | Evaluate an expression or `--file`; `--json`, `--target`, and `--timeout` are available | yes for file input |
| `fmt` | Canonical formatter (`--check`, `--inplace`) | gate subject |
| `lint` | Naming/style rules (`--check`, `--fix`, `--list`, `--rule`) — `spec/01-nomenclature.md` | gate subject |
| `lane-check` | Compare evaluator and compiled-C stdout exactly over a file or corpus (`--json`, `--timeout`); see §6.3 | yes, through its `eval --file` and `build` runs |
| `cost` | Report lowered-IR copy cost (`--json`) | no |
| `deep` | Desugar Surf → Deep s-expr (`--annotate`) | no |
| `surf` | Resugar well-formed public Deep → canonical Surf; invalid or unpreservable metadata is an error | no |
| `migrate` | Explicit `surf`/`deep` source migrations from a named older grammar; normal parsing does not silently migrate | command-specific |
| `prove` | `@property` verifier (`--tier`, `--samples`, `--seed`, `--smt-timeout`, `--capabilities`); see §12 | no |
| `test` | Run Chelis-native tests (`--filter`, `--json`, `--jobs`, `--expect`, `--batch-mode`) | no |
| `tide` | REPL / HTTP API / MCP / LSP entry points (`serve`, `lsp`, and MCP mode) | no |
| `cove` | Terminal UI (`--file`) | no |
| `reef` | Package, artifact, setup, and conformance commands (`init`, `update`, `build`, `install`, `setup`, `conform`, and others) | no |
| `runtime` | `export <dir>`: write the carried runtime archive, public headers and staging receipt | no |

The style gate (`fmt --check` + blocking `lint`) runs inside `build`, `check`,
`validate`, and `eval --file` where a Surf file is subject to the gate.
The CLI provides `--allow-style-violations` for emergency local use;
`CHELIS_STYLE_GATE_DISABLE=1` is reserved for the integration-test corpus.
Inline `eval` snippets do not run an on-disk file style gate. `fmt`
is the canonical spelling check (`spec/02` §0.1), while `deep` and `surf`
expose the two source representations.

---

## 11. Bundled `chelis-std` — `packages/chelis-std`

`chelis-std` ships with the selected compiler toolchain. Its module
exports are the `export` declarations under `packages/chelis-std/src/`.
Concrete calls depend on their target execution mode. Neural-network layers,
losses, optimizers, and training loops live in a shell, not in `chelis-std`
(`spec/design/chelis_canonical_reference.md` §8.5).

| Module | Key exports |
|---|---|
| `Std.Tensor.Construct` | `linspace`, `arange`, `stack`, `squeeze`, `unsqueeze`. `Float`/`Int` bounds are checked; some concrete calls have gaps ([#1416](https://github.com/Chelis-Lang/chelis/issues/1416)). |
| `Std.Tensor.Mask` | `where_indices`, a source-defined mask index helper. |
| `Std.Sort`, `Std.Scan`, `Std.Index` | `sort`; `scan_list`; `list_index`, `take_list`, `skip_list`. The `sort` wrapper and host builtin return `i64` indices. Selected List index/selection adjoints have Eval/C coverage. |
| `Std.Io` | `read_text`, `write_text`, `read_trimmed_lines`, `read_head_bytes`, `exists`, `list`, `mmap_size`. |
| `Std.Io.Csv` | `read_csv`, `try_read_csv`, `to_csv`, `try_to_csv`, `write_csv`, `try_write_csv`. These are source-defined functions, distinct from the eval-only CSV builtin family. The line-based reader and serializer do not accept CR/LF inside a cell. |
| `Std.Io.Json` | `Json` with `JsonNull`, `JsonBool`, `JsonInt`, `JsonBigInt`, `JsonFloat`, `JsonString`, `JsonArray`, `JsonObject`; parsing, serialization, file I/O, accessors, and `try_*` forms. Integer tokens preserve the `JsonInt(i64)`/`JsonBigInt(string)` distinction instead of passing through `f64`; decimal/exponent tokens use `JsonFloat(f64, string)`, keeping the token text beside its correctly rounded `f64`. |
| `Std.Io.Parquet`, `Std.Io.Safetensors` | `read_parquet`/`write_parquet`; `save_tensors`/`load_tensors`. Check concrete dtype, shape, and target support for a selected call. |
| `Std.Scalar`, `Std.Text`, `Std.Test` | Scalar `max`/`min`/`abs`; `join`; assertions, shape checks, and failure helpers. |
| `Std.Datetime`, `Std.Datetime.Business`, `Std.Datetime.Clock`, `Std.Datetime.Columns`, `Std.Rounding`, `Std.Decimal`, `Std.Process`, `Std.Contracts` | Validated dates, times, instants, offsets, durations, periods, and date/instant columns; business-day calendars over a declared horizon; the host wall and monotonic clocks, which carry `IO`; elementwise column forms and a `Durations[n]` column; the shared rounding modes; exact 38-digit decimal arithmetic; `run`/`run_chelis`; named contract predicates. |
| `Std.Datetime.Zone` | `TimeZone` values read from TZif bytes the program supplies (`time_zone_from_tzif`) or fixed (`time_zone_fixed`, `time_zone_utc`); `Zoned` values with local-reading resolution under a required `Disambiguation`, and RFC 9557 text resolved under a required `OffsetConflict`. |

Compiled-host support for a source-defined module depends on its
selected dependencies and execution path.
For example, `packages/chelis-std/tests/io/json.ch` and `io/csv.ch`
exercise the respective modules, while the builtin CSV family has a
separate build rejection (§3.9). `Std.Tensor.Reduce` is absent; call
`min_reduce`, `prod_reduce`, `argmax_reduce`, or `argmin_reduce` with a
statically resolved axis instead.

---

## 12. `@property` and `chelis prove`

`@property` declarations desugar to a `bool`-returning `def` tagged
`chelis_role: "property"`, with typed binders and optional `where` preconditions and
`with tolerance|seed|samples|contract` metadata. The property spec lives in
[`spec/design/chelis_property_spec.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/design/chelis_property_spec.md);
the executable dispatch is in `crates/chelis-prove/src/property_runner.rs`.

| Tier / option | Route |
|---|---|
| `induction-only` | Surf structural-recursion subset: separate base and step SMT obligations; unsupported shapes stop without sampling. |
| `smt-only` | Lowerable arithmetic and supported contract/gradient forms go to SMT; unsupported forms do not become sampled passes. |
| `fuzz-only` | Deterministic typed sampling with `where` precondition filtering; an observed pass is empirical evidence. |
| `type-only` | Type-oriented result without a proof artifact. |
| `beacon-only` | Optional feature-gated scalar bound-propagation route; `--capabilities` reports availability for the selected build. |

`--tier auto` tries induction first for a checked Surf property that
reaches a recursive model; that outcome is terminal. Otherwise it tries
the SMT route and then sampling for a goal outside the supported SMT
subset. Deep properties do not use the Surf-only induction classifier.
The machine result distinguishes proved, disproved, unsupported,
timed-out, and sampled outcomes; real-arithmetic qualifications and
contract assumptions must be read with the verdict. A host-runtime
operation is not automatically SMT-lowerable, and a sampled pass is
not a proof.

---

## 13. Where to read more

| Doc | Why |
|---|---|
| [`spec/02-surf-syntax.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/02-surf-syntax.md), [`spec/03-deep-syntax.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/03-deep-syntax.md) | source syntax, canonical Surf/Deep conversion, and metadata |
| [`spec/04-type-system.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/04-type-system.md) | dtypes, shapes, accumulators, effects, and linearity |
| [`spec/05-risc-primitives.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/05-risc-primitives.md) | operation signatures, traps, and adjoints |
| [`spec/06-transformations.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/06-transformations.md) | `grad`, `vmap`, and `jit` semantics |
| [`spec/08-backends.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/08-backends.md) | backend strategy and target constraints |
| [`spec/design/differentiable_language.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/design/differentiable_language.md) | implementation sequence for broader AD |
| [`spec/design/rank_polymorphism.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/design/rank_polymorphism.md) | rank-polymorphic implementation |
| [`spec/design/implicit_linearity.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/design/implicit_linearity.md) | ownership implementation |
| [`spec/design/chelis_canonical_reference.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/design/chelis_canonical_reference.md) | core, stdlib, and shell boundary |
| [`spec/design/shell_repo_contract.md`](https://github.com/Chelis-Lang/chelis/blob/v0.18.13/spec/design/shell_repo_contract.md) | a downstream shell's required surface view |

### Deep metadata and source conversion

`spec/03` [03-META-1..3] owns registered metadata, producer extensions,
and their placement. Ingress rejects malformed values, duplicate keys,
and forbidden placements with the key and source location. Extension
payloads are opaque data, not executable subtrees; semantic rewrites
preserve them without interpreting a nested variable spelling or macro
form. Surf conversion rejects an extension it cannot preserve. `grad`'s
`wrt` metadata uses a variable reference or a nonempty tuple of them,
not bare names.

Rust callers receive typed `Metadata`/`MetadataValue` and sealed
`ExtensionData` rather than an unchecked expression map. The
`chelis_surf::resugar::normalize_deep_for_surface_roundtrip` API is
fallible: handle its `ResugarError` before using normalized Deep as a
round-trip witness. `chelis deep`/`surf` are the CLI views; `spec/02`
§0.1 gives the canonical conversion laws.
<!-- END CHELIS MANAGED BLOCK: chelis-surface -->

# Chelis Capability Surface for Shoals

**Candidate compiler pin:** Shoals 0.24.14 / Chelis 0.18.13 /
chelis-std 0.4.0. Nautilus 0.7.47 and Coral 0.7.44 are the last published
sibling packages, both built for Chelis 0.18.12. A complete 0.18.13 package
build awaits Nautilus 0.7.48 and Coral 0.7.45 releases. The prior 0.18.12
compiler and oracle receipts are recorded in
[`chelis_0_18_12_migration.md`](chelis_0_18_12_migration.md); they do not
validate this compiler pin.

What the Chelis language and the bundled chelis-std actually provide to the
quantitative-finance domain this shell touches — numerical methods, pricing,
Greeks, and the proof surface over them. **Read this before designing around a
suspected language gap.**

> **Candidate compiler pin:** Shoals 0.24.14; Chelis 0.18.13
> (chelis-std 0.4.0, bundled). Published Nautilus 0.7.47 and Coral 0.7.44
> remain at Chelis 0.18.12 pending their next releases.
> · **Partial refresh:** 2026-10-05

The last accepted package-chain receipts are in
[`chelis_0_18_11_migration.md`](chelis_0_18_11_migration.md) and the historical
0.18.11 section of the CNote manifest. The release-specific narrative below is historical
de-narrowing evidence.

**Published Nautilus input for the candidate bump.** Annotated tag `v0.7.47`
dereferences to commit `76a66ae921cafeef538e1ff48ea53fdc253c1724`.
The downloaded `nautilus-0.7.47.chb` is SHA-256
`cd5c04ecfcd2445b7f7a7e0a997d721f20c85aac4524ae626571c3db96008603`;
the archive is
`dfe18e834c2d6e49282afd682e0452e51575c3d1dcefd4db3267098e98bba716`.
Both match the release sidecar. The archive declares compiler `=0.18.12`;
its 25 source modules retain the 0.7.46 exported-name sets. Coral 0.7.44's
published archive declares the same compiler pin and Nautilus 0.7.47;
its CHB is `5e69584d3e967aef72c6ae18b0204b00b155804876ece8d7feda604c6c0263b3`
and archive is
`7cc0ed3ede5ab754615465704ec0f9bd01bb7ccabba10cb50770c6c78c3e3ba5`.
These are the hashes in the generated Shoals lock.

## Historical 0.18.6 de-narrowing record

The published Chelis `v0.18.6` tag resolves to commit
`cf49f85bf0d1bca2c87c88a3e459c446912189c0`. Release workflow `33232762790`
completed successfully; the publisher-authenticated Darwin arm64 archive
has SHA-256 `08580435570c6fd44716f4d5c64117e973e379808cefeaaa97c8faefa2588f6c`
and its extracted compiler payload has SHA-256
`1c88c737d7d3740eb4adbe7b50ea31d29ee64498b9d74b35664255ca16aea8d4`. Both were
re-derived from the downloaded asset here, and that payload hash is
byte-identical to the toolchain every measurement in this bump ran on. The
glibc-2.31 archive for the same tag has SHA-256
`fb9ef6701fbf0ef2532bcbafb213ca80c21d7b13da0b341b55c64ba89aa8e8fa`;
it is sidecar-verified but exercised by CI rather than this gate run.

**0.18.6 is the largest breaking cut since 0.18.0, and almost all of it is at
a machine boundary this shell does not touch.** Probed against the corpus
rather than reasoned about, one BREAKING change reaches Shoals and six do not.

*Reaches this shell.* **The exported stdlib surface is aligned with
`[05-OP-35]` (chelis#1293/chelis#1314).** `Std.Test` no longer exports
`assert_eq_int`, `assert_eq_bool`, `assert_eq_string`, or
`assert_eq_tensor_int64`; the replacement is one polymorphic
`assert_eq[q](actual, expected, label)`. Shoals imported two of them (`assert_eq_int`,
`assert_eq_bool`) at 26 call sites across 7 files, all migrated in this change
set along with those files' 7 `import Std.Test (...)` lists -- 33 token
occurrences in total. Confirmed as a measured
pair, not read off the changelog: the identical file runs `2 passed, 0 failed`
on 0.18.5 and fails on 0.18.6 with ``module `Std.Test` does not export
`assert_eq_int` for import into Probe.__Eval``. `assert_close` survives with a
widened signature (`[p_float]` rather than `f32`), which is a loosening and
needed no edit. `assert_shape` also changed shape (`List[int64]` extents rather
than a single `int64`) but Shoals never used it.

*Does not reach this shell, each checked against the corpus.* (1) The **C ABI
replacement** (`chelis_scalar` tagged carriers, `chelis_dtype`, dynamic-rank
tensor metadata, one-byte `bool`) matters only to a consumer compiling against
`chelis_runtime.h`; Shoals links no runtime and targets no HIP. (2) **`diagonal`
and `trace` returned out-of-bounds heap bytes** for every axis pair except
`(rank-2, rank-1)` (chelis#1349) — the corpus calls neither builtin at all;
`bootstrap_grad_diagonal` in `src/curves.ch` is a local `def` whose name merely
contains the word. (3) **`JsonBigInt(string)` is a new `Json` variant**, so a
previously exhaustive `match` over `Json` is not exhaustive now — Shoals has no
`Json` value, no `parse_json` call, and imports nothing from `Std.Io.Json`;
Coral fixed its own two `match` sites. (4) **`init/xavier::sample` and the
legacy JSON aliases are removed** — unused here. (5) **WireDag advances to
schema 6, exact-only** — Shoals *does* consume this, but through its own gate
rather than as a break; see the WireDag row below. (6) **HIP rejects `bool`
tensors** and **every on-disk cache is invalidated** — no HIP target, and cache
invalidation is automatic.

*Not a break, but it changed a pinned artifact.* **`sub` became a first-class
WireDag identity** ([05-OP-40], chelis#1306) instead of being reconstructed as
negate-then-add. Shoals pins the lowered Black-Scholes DAG byte-exactly in
`scripts/validate_bs_wire_root.py`, so this moved real numbers: 23 `sub` nodes
appear while `add`, `neg`, and `drop` each fall by exactly 23, every other op
kind is unchanged in count, and the DAG shrinks 1018 -> 972 nodes with the
entry root moving 535 -> 512 and its op changing `add` -> `sub`. Audited by
lowering the same `src/pricing.ch` under both binaries and comparing op-kind
histograms, not by accepting the new hash.

**0.18.2 is skipped.** The 0.24.6 / 0.18.2 candidate could not land: Nautilus
0.7.39 worked the chelis#759 float-to-integer trap around with `floor(...)`,
which has no compiled-lane expression identity, so Coral's native build broke
and its 0.7.36 release never happened. Chelis 0.18.3 ships `cast_trunc`
([05-OP-6]) and Nautilus 0.7.40 moves onto it.

**The sibling half of this chain is published.** Reef enforces exact
compiler-pin equality on dependencies, so this pin could not resolve against
Nautilus 0.7.42 / Coral 0.7.39 (both declare `=0.18.5`); the sibling releases
landed ahead of the Shoals 0.24.10 release and the cascade is closed.
**Nautilus 0.7.43** (`Chelis-Lang/nautilus#50`, merged as
`7e3451b4977922d0bda80883ba385c7da211fc9e`, tagged `v0.7.43`) has CHB
`c3e6fb6e2c3a397726df0cc53587d854ac48cab416c9dea80c9df717bfe0ef4d` and archive
`970fb4ff51e6dfdce3043bb6ad772a7df74fd4c05a0be2723d451b35ef7ddd05`;
**Coral 0.7.40** (`Chelis-Lang/coral#29`, merged as
`301305312186888856d6645eb7c898c27af28ff3`, tagged `v0.7.40`, itself declaring
`nautilus = "0.7.43"`) has CHB
`672297eb6bafcffb8f3c4ad867f59aecece8cf114747fbfe2a112f3346edc2f1` and archive
`a6416fa595b092b34f1d5483429f65b4e19927db833288a18919d5b497ecc08f`. All four
were re-derived from the downloaded assets and match their published sidecars,
and both declare `compiler = "=0.18.6"`.

The 0.24.10 gate ran against exactly those published artifacts, installed with
`chelis reef install --from-github` into an isolated registry
(`CHELIS_REEF_HOME` pointed away from the shared store). A downstream consumer
declaring `shoals = { version = "0.24.10" }` resolves the whole chain and
builds, which is the end-to-end check that matters for C Note. During
authoring, before the sibling releases existed, the same gate ran against
local builds of each sibling's PR head; those local hashes differ from the
published ones (Coral artifact bytes remain install-path dependent under
chelis#1002) and are deliberately **not** recorded here or in
`docs/cnote-import-surface.json`, whose retained-evidence list takes only
sidecar-verified published hashes.

The previous chain's published artifacts, retained for de-narrowing: Nautilus
0.7.42 from commit `85d88133b0aaf5fde3a0f425dca4a1e5fa1056de`, CHB
`f5ed24c05c4e20fdf6c72601e2e9dd68cf46a63730eb79d9189adc493704f028`, archive
`fcdf32e581d95a43b0c37d672ff241348f75f308179d0b03f6f79a5247506f95`; Coral 0.7.39
from commit `8da830db79a561c5e97fb4592f3fea2fbc492641`, CHB
`b54e8a410a3f747f0a02dc6fb8496d9fe868c288d6db1ffb2f634664f499835a`, archive
`38149dab1bceed366dc93bc62f6e3f46e21fe4d27af49510ca024bc66d16a77f`. All four
were re-derived from the downloaded assets here and match their published
sidecars.

The 0.24.10 candidate's `scripts/prove_gate.py` run consumes the 0.18.6 chain
above with its fuzz lane on (`PROVE_GATE_FUZZ=1`), green in 1m59s against
3m29s at 0.18.5 on the same machine. Its
Shoals#37 lanes observed both risk families at `fuzz_validated`: all six
properties accepted 25 constraint-directed samples at each seed 0, 1, and 2;
every corrupt control produced an in-domain witness; and the compiler summary
graph supplied every direct function edge, including the second CVaR edge in
both dominance relations.
Its Shoals#42 lane separately binds seven actual AD outputs and the displayed
price to their compiler-reported shared `bs_call_f64` body. Those records carry
runtime-oracle and multi-seed fuzz evidence; certified-box and global proof
remain explicit Shoals#42 deferrals.

The previous validated Chelis `v0.17.4` baseline resolves to commit
`0b0c92f9916163b05a483fba70473496923730e6`. Its downloaded
`linux-x86_64-glibc2.31` archive has SHA-256
`6b7f477d65b2dea4e85b5107a51ae5714a5113138a6791361b74205f9448a121`;
its `chelis` binary has SHA-256
`d08ebfe67fed11f4458251d47e732de3249d93a3d700c87991a39e219887cc7e`.
The publisher sidecar verified the archive before installation.
The official Nautilus `v0.7.36` tag resolves to commit
`2c434a9dfefca79c371b4c66af62b121a47841d6`; its canonical CHB and archive
SHA-256 values are
`2db566d8b381fd4d49acef62f875420a59c397961954a7c27cb02b79cb3f12e4`
and `412e24ec26f1828db394f6bed6ef8f4a9c93a7b104e020a457c93ec0a5b96572`.
The official Coral `v0.7.33` tag resolves to commit
`7bda6af8210a4dc128147e64cdb82019d27308f3`; its canonical CHB and archive
SHA-256 values are
`a3e04e308eb7d35c34fe4d6075c7e7626c57a6a9957fc6cf9926467b5787ec6c`
and `fe41f1617b118eb1600d02518319a96780c77195cce4c836ec43776bd69e08b0`.

Rows marked `@pin` carry 0.18.6-chain evidence. `@upstream` remains a
later capability that is not shipped at this pin. Refresh this table at every pin bump
(`AGENTS.md` §Pin Bump Checklist). The authoritative depth reference for the
proof reachability map is
`research/proof-infra/report.md`; the source-of-truth for the cvc5-lowerable set
is chelis `crates/chelis-prove/src/tier_b.rs` (`CVC5_LOWERABLE`).

## Proof surface — `chelis prove` (the spine of the finance verification story)

`chelis prove [PATH] --tier auto|smt-only|fuzz-only|type-only [--json]`, three
tiers: **A** (type/dimension/linearity), **B** (SMT via cvc5 over the reals),
**C** (seeded fuzz with precondition/invariant rejection sampling).

| Capability | Status | Notes |
|---|---|---|
| SMT prove tier (cvc5) shipped in the **release** tarball | `@pin` | SMT is in the released binary as of chelis 0.11.0 (no from-source `--features smt` build needed at this pin). Tier B lowers to cvc5 over the **reals** (`QF_NRA`, or `QF_NRAT` when a transcendental is present); a green is a real-arithmetic fact, **not** an IEEE-`f32` statement. `arith_model:"real"`. |
| Transcendentals `exp`, `sqrt`, `sin`, `cos` lower to SMT | `@pin*` | These four **do** lower — cvc5 kinds `EXPONENTIAL`/`SQRT`/`SINE`/`COSINE`, selecting the `QF_NRAT` logic. *`QF_NRAT` is **incomplete**: cvc5 may return `unknown`, which chelis records as `unsupported` (solver capacity) and `--tier auto` degrades **honestly** to fuzz — never a false proven. Keep structural greens transcendental-free by construction where possible (report §3). |
| Certified-envelope transcendental discharge (`erf`/`normal_cdf`/`exp`/`log`/`sqrt` subterms) | `@pin` | Shipped in 0.16.0 (**chelis#434, now CLOSED**): a soundly-boundable transcendental subterm is abstracted to a fresh variable over its Gappa/Arb-certified envelope hull and the goal discharges as **`proven_modulo_certified_envelope`** (strictly weaker than `proven_modulo_real_arithmetic`, disclosed in the verdict). Fail-closed on unboundable arguments. **Residual:** goals whose truth depends on the *coupling* between abstractions cannot reach an exact proven tier: direct BS/B76 call-price positivity and direct BS spot-monotonicity/delta, vega, rho, and gamma comparisons are observed only at `fuzz_validated`, while the direct intrinsic-lower-bound candidate remains `deferred_invariant` (**chelis#637**, open). See `UPSTREAM_BUGS.md`. |
| `erf` / bundled `n_cdf` via an abstract-subterm contract | `@pin` | `erf` is not directly cvc5-lowerable, but the bundled normal-CDF **contract** (`0 ≤ N ≤ 1`, reflection `N(-x)=1-N(x)`) is discharged at the SMT tier as an abstract subterm (`chelis-prove/src/contracts.rs`), which is what lets the abstracted derivatives structure prove. The contract is separately fuzz-validated against the real `n_cdf` (max abs err ≈ 2 ulp vs scipy, report §7) — that is an **`f32`** measurement: `research/proof-infra/oracle/compare_ncdf.py` uses `ULP_F32 = 2^-24 ≈ 5.96e-8` and `RESULTS.md` records the max as **1.22e-7 at x=0.75**. It is not a claim about `n_cdf64`, which no longer shares that kernel: `erf64` moved to Cody's approximation (>= 3.3675e-16 observed) while `Nautilus.Special.erf` — the path this row measures — still evaluates A&S 7.1.26. The two are now different approximations, and the ~1.2e-7 figure belongs to the `f32` A&S one. See the accuracy section below. |
| Algebraic `abs`, `min`, `max` lower to SMT | `@pin` | In `CVC5_LOWERABLE`, `QF_NRA` (algebraic, not transcendental). `min`/`max` lower to ITE. |
| Composite derivatives greens | `@pin` | `properties/composites.ch`: structure proven at Tier B for any `N` satisfying its contract, verdict `proven_modulo_fuzz_validated_contract`. This string is **legitimate here** (a real SMT base resting on a fuzz-validated contract); it was only a false-positive for **pure-fuzz** bases, fixed by chelis#435 (archived). Classify verdicts from `proof_tier`, never the string alone. |
| Economic / dynamic-programming greens | `@pin` | Markov simplex preservation, Bellman monotonicity/boundedness/contraction, PV/Gordon positivity & monotonicity discharge at SMT with **no** transcendental contract (report §6). Structurally more complete than a derivatives green. |
| Function-call inlining depth for SMT | `@pin` | Nested calls inline to `MAX_INLINE_DEPTH = 3` (`chelis-prove/src/tier_b_lower.rs`); deeper chains route to Tier C. No shoals goal hits this today; c-note probe `p07` pending (`UPSTREAM_BUGS.md`). |
| Beacon (large-scale concrete verification) | `@upstream` | `beacon_available=false` in the release binary; gated on `CHELIS_BEACON_BIN`. Shoals now provides the real-pricer `bs_call_wire_f64` tensor root (shoals#19); bounded-domain consumption remains Beacon#74. The 0.18.6 Beacon request envelope moves to schema 2 with a `wire_dag_v6_base64` field, so a Beacon deployment must upgrade in lockstep; there is no one-way read migration as there was for v5. |
| prove-side import resolution | `@pin` | `prove` resolves package imports, so a property targets the real exported function; standalone structural probes are self-contained (report §2). |
| Constraint-directed property sampling | `@pin` | Chelis 0.18.3 ships chelis#977 guard-directed generation. Shoals#37 requires and observes 25/25 accepted samples at each of seeds 0, 1, and 2 for both parametric and historical risk families; a starved or partially accepted run fails the gate. |
| Linked Nautilus quantile contract identity | `@pin` | Chelis 0.18.3 binds `std.quantile.monotonicity` only to the linker-owned `Nautilus.Stats.quantile_vec` (chelis#979). Shoals keeps historical wrapper claims at the observed `fuzz_validated` tier and never reconstructs the wrapper relation from source text. |

## Numeric & language primitives the domain uses

| Family | Status | Notes |
|---|---|---|
| Arithmetic `+ - * /`, comparisons | `@pin` | Lower to cvc5. Keep `/` out of SMT goals where possible; use multiplied-through polynomial form. |
| `if/then/else` | `@pin` | Lowers as ITE in `QF_NRA`. |
| `Option[T]`, `Some`/`None`, `match`; `@opaque` + `@invariant` | `@pin` | Opaque-invariant abstraction is the path from synthetic green to a green a quant recognizes (report §1, §3); producer obligations discharge at SMT. |
| `Std.Test` (`assert_close`, `assert_eq`) | `@pin` | The executable numeric suites under `tests/` and `tests-manual/`. **Changed at 0.18.6:** `assert_eq_int` / `assert_eq_bool` / `assert_eq_string` / `assert_eq_tensor_int64` are gone with no alias; use the polymorphic `assert_eq[q](actual, expected, label)`. `assert_close` widened from `f32` to `[p_float]` — a loosening, and its tolerance must now share the tensors' dtype in `assert_close_tensor` (unused here). |
| WireDag lowering (`chelis tide serve` `/lower`) | `@pin` | Schema **15**, exact-only. Shoals pins `bs_call_wire_f64` byte-exactly in `scripts/validate_bs_wire_root.py`: 1665 nodes, entry root 859, raw SHA-256 `811f1cda0a046bbe5e24c51514e9f266815849e9824184786c0b9d93e32ad546` (re-pinned for shoals#101's expiry limits, no compiler change; shoals#88 pinned `11db7522…` at the same root and node count, and the pre-0.18.11 figures were 1522 / 787 / `3be34d90…`). The 0.18.10-to-0.18.11 comparison below was measured on the pre-shoals#88 source and does not compose with the figures above: against 0.18.10 that source gained 14 `Copy` and 14 `Drop` nodes and `cmp_lt` became `compare(comparison=lt)`, with copy-elided dataflow, op parameters, precisions and 15 named loads agreeing. Symbolic dimension names differ, so no shape-equivalence claim is made. |
| Front-end check throughput | `@pin` | The compiler surface is available. The 0.18.6 measurements (31.6s for `src/modelfit.ch`, 17.0s dependency-load floor, and a 7m54s batched-suite observation) remain historical measurements, not 0.18.11 performance claims. The pin-bump full gate owns current acceptance. |
| `count` ([05-OP-29]), direct `sub` / `min_elem` ([05-OP-40]/[05-OP-41]) | `@pin` | Shipped before this pin and available, though Shoals does not currently depend on them. |
| `stop_gradient` ([05-OP-42]) | `@upstream` | The contract exists, but implementation remains open in chelis#1312; Shoals does not claim it at this pin. Relu's dedicated adjoint is a separate closed issue (chelis#1313). |
| `to_list` / `to_tensor` over `tensor[n, f64]`, incl. a generic `[n]` ([05-OP-57]) | `@pin` | Load-bearing for all 22 `tensor_` exports of `Shoals.Indicators`: each delegates to its list counterpart over `to_list` -- one conversion per tensor series, so the multi-series forms do two or three, and the two crossing forms do none directly, reaching it through `ind_mask_tensor` (shoals#83, `spec/shoals_quant_surface.md` §2.15.5). Order and length preserved; a symbolic `[n]` composes. Distinct from the `@upstream` grad row below, which is about differentiating *through* such a body, not about the conversion. |
| chelis-std / nautilus / coral module surface | `@pin` | Pricing, distributions, RNG, curves, dates, vol surfaces per `src/` + `references/`. |

## Numerical accuracy of shell-authored kernels

What the kernels this shell authors actually guarantee. It exists because dtype
is not accuracy: an `f64` signature says how the arithmetic is evaluated, not
how good the approximation being evaluated is.

**Every figure below is measured on the compiled kernel against a high-precision
`mpmath` reference, not derived.** Where a bound is not measured it is not
stated.

`scripts/oracle_erf64_accuracy.py` computes them, measuring in binary at
extended precision; `erf64` and `n_cdf64` are exported so the bound can be
measured from outside the module. **The table below is the authoritative
publication of these figures, and the oracle reads it** — it no longer compares
against internal constants of its own (shoals#64). Two legs check it:

- Every PR runs the oracle's offline `--transcription` leg, which parses the
  floors out of this table and requires every other place in the tracked tree
  that states one of them to state the same number. Carriers are discovered by
  `git grep`, so adding one needs no registration and a stale one cannot hide.
- The nightly job runs `--measurement`, which measures the compiled kernels
  against a 60-dps reference and requires each floor here to be a **true and
  tight** floor: equal to the measurement truncated toward zero at that
  figure's own significant-digit count. Publishing fewer digits is allowed;
  publishing an understated floor (`1.0e-30` is technically a floor) is not.

The division is deliberate — the offline leg proves the carriers agree, never
that they are right, and only the nightly leg constrains the value. A missing
`mpmath` now fails the measurement leg instead of skipping it.

| Kernel | Approximation | Worst observed absolute error (a floor) | Method |
|---|---|---|---|
| `erf64` | W. J. Cody, Math. Comp. 23 (1969); three ranges split at 0.5 and 4, saturating at 6 | **>= 3.3675e-16** (~1.52 ulp of 1.0) | worst observed at x = ±0.507001975 (`erf` is odd, so the error magnitude is identical at both signs and the oracle may report either; `n_cdf64` below is **not** symmetric and its sign is significant), measured at 60 dps by `scripts/oracle_erf64_accuracy.py`; the error is jagged at ulp scale so any grid reports a floor |
| `n_cdf64` | `0.5 * (1 - erf64(-x/√2))` | **>= 1.9495e-16** (~0.88 ulp of 1.0) | worst observed at x = -0.7170090691949448, measured at 60 dps by the same oracle. NOT `erf64`'s halved: the argument reduction `-x/√2` and the final `0.5 * (1 - e)` each round. **ABSOLUTE only — see the left-tail limitation below** |

**`n_cdf64` has no useful RELATIVE accuracy in the left tail.** Both figures above
are absolute errors, and the oracle that produces them sweeps absolute error over
±6.5, so it cannot observe this. `erf64_erfc_abs` computes `erfc` to ~1 ulp, but
`n_cdf64` routes it through `1 - erf64` and `erf64` is itself `1 - erfc`, so the
two subtractions cancel that precision away as the result approaches zero.
Measured on the shipped kernel: **2.3e-6 relative at x = -7, 1.8% relative at
x = -8, and exactly `0.0` below about x = -8.3** where the true value is ~1e-17.
Do not use `n_cdf64` for deep-tail probabilities. Routing the negative branch
straight through `erf64_erfc_abs` would keep the relative accuracy; that is
shoals#68.

**The kernel is no longer the limiting factor for the price and the Greeks**
(the left-tail exception above is `n_cdf64`'s spelling, not the kernel).
`bs_call_f64(100, 100, 0.05, 0.2, 1)` returns `10.450583572185565`. Against the
f64 values of those decimal inputs — the ones the kernel actually receives — the
exact price is `10.450583572185567346`, whose correctly-rounded f64 is
`10.450583572185568`, so the returned value is 1.51 ulp (two representable
steps) from it. Quoting a reference computed from the decimal spellings instead
gives `10.45058357218556678` and makes it look like one ulp; the figure above
uses the f64 inputs, matching the `f32`-rounded-input discipline the Greek table
below states. The `f32` Greek exports land within ~1 `f32` ulp of their true
values —
that is their dtype's rounding, not the approximation's error:

Measured at `K=100, r=0.05, sigma=0.2, T=1`, worst case over
`S in {60, 80, 100, 120}`, comparing the shipped `f32` exports (`chelis eval`)
against a 50-digit `mpmath` reference evaluated at the same `f32`-rounded
inputs. The two columns are each a worst case over those spots and need not
fall at the same spot.

| export | error vs true | in `f32` ulp |
|---|---|---|
| `deltas_call` | 5.17e-8 | 0.87 |
| `vegas_call` | 1.33e-6 | 0.37 |
| `rhos_call` | 2.44e-6 | 0.41 |
| `gammas_call` | 6.53e-10 | 0.35 |
| `thetas_call` | 1.15e-7 | 0.32 |

**No bound is stated for the Greeks.** The error of a derivative is not
controlled by the error of the function — in Black–Scholes the true
`S·φ(d1) − K'·φ(d2)` terms cancel exactly while an approximation's do not, and
the residue is amplified by `√T/σ` or `1/(Sσ√T)`. The table above is a
measurement at one parameter set, not a bound over the parameter space.
Deriving one is out of scope here.

**What this replaced.** Abramowitz & Stegun 7.1.26, whose ~1.4e-7 bound is a
property of its coefficients rather than of the arithmetic evaluating them — so
the `f64` entry point was no better than the `f32` `Nautilus.Special.erf` whose
coefficients it copied, and no wider cast could have improved it. A ~4.1e8x
reduction. That was this shell's issue 61.

**Still hand-rolled, pending a package-chain comparison.** Chelis 0.18.13
adds correctly rounded `erf` and `erfc` primitives; the former absence probe
is now the passing `tests/canonical_erf.ch`. Shoals's scalar Cody kernel has
not yet been replaced because its Greek and expiry behavior has not been
measured on the compatible Nautilus/Coral release chain. The broader
special-function request chelis#902 remains open. Nautilus 0.7.47 makes
`Nautilus.Special.erf` callable at `f64`, as the
test `tests/nautilus_erf_f64.ch` observes in an isolated Nautilus-only package,
resolving the nautilus#59 signature barrier. It retains A&S coefficients whose f64
approximation gap is tracked by nautilus#74. Replacing Shoals's Cody kernel
with it would discard the measured f64 accuracy.

**Not covered here.** `Shoals.Greeks`'s `analytic_delta_call` /
`analytic_delta_put` use a local `n_cdf` over `Nautilus.Special.erfc`, still the
`f32` A&S path; `analytic_vega_call` / `analytic_gamma_call` use `n_pdf` and
never touch `erf`; the `fd_*` Greeks and `src/volsurface.ch` / `src/dupire.ch`
divide price differences by `h`, `h²` or vega and so amplify whatever error
remains; `Shoals.PricingExtended`'s `n_cdf_ext` and
`references/blackscholes.ch` are **call sites, not copies** -- both
`import Nautilus.Special (erfc)` and carry no coefficients of their own, so
they inherit whatever that f32 kernel does and need no migration. An earlier
revision of this paragraph called them "further copies of the A&S kernel",
which is false: no file under `src/` or `references/` carries the A&S
constants. `pricing_wire_erf_f64` is the real remaining case, and only in the
sense that its coefficients are caller-supplied tensor parameters. The duplication that does exist is
wider than "one kernel per repository", which an earlier revision of this
paragraph claimed. Inside this repo there are four `.ch` erf bodies:
`src/pricing.ch::erf64` (Cody's), `src/pricing.ch::pricing_wire_erf_f64`
(A&S, caller-supplied coefficients), and A&S with hard-coded f64 literals in
both `research/proof-infra/ad/src/bs.ch` and
`research/proof-infra/graduation/src/probe.ch` -- each its own reef project,
all in this repository -- plus TWO Python mirrors,
`research/proof-infra/ad/harness.py` and
`scripts/oracle_greeks_gate.py::_erf_as_f32`. The second is the one with a live
maintenance trigger: it models `Nautilus.Special.erf` and must be re-measured at
the next Nautilus kernel change (see `docs/UPSTREAM_BUGS.md`).
Since `erf64` moved to Cody's these are no longer copies of one
algorithm but two different ones, so it is drift rather than redundancy, and
drift is the harder case: a caller cannot assume they agree at all. Tracked by
nautilus#74 and chelis#902; nautilus#59 resolved the signature barrier.

**Scope.** These are kernels this shell authors. Accuracy of chelis primitives
is upstream's, and upstream has no accuracy contract for shells to inherit —
chelis#1563 proposes one.

## Automatic differentiation (`grad`) — the Greek-set surface

| Capability | Status | Notes |
|---|---|---|
| `grad` reverse-mode AD in `eval` / host runtime | `@pin` | The four first-order call Greek outputs evaluate through the real Black–Scholes and normal-CDF body. The 0.18.12 Greek oracle passes 15 groups and 63 cells, including second-order outputs. Reverse-mode; scalar floating result required. |
| `grad(grad(...))` second order | `@pin` | Gamma/volga/vanna exports use nested `grad` through the displayed Black–Scholes price body. The 0.18.12 raw sampled controls pass at seeds 0, 1, and 2, and all four `tests-manual/greeks_secondorder.ch` cases pass. Keep the scalar kernel's sequential conditional spelling while chelis#2825 remains open. |
| `vmap(grad(...))` batched sensitivities | `@pin` | True batched grad over a spot×vol grid, validated vs analytic `N(d1)` (report §5). |
| Host-lane list-combinator pricing body under `grad` | `@upstream` | The shipped per-spot `to_tensor(map(..., to_list(...)))` body does not lower under `grad` (rank-0 `sum`); identical pure-tensor-lane math differentiates fine. Graduation candidate: a tensor-lane grad-able BS body (ties to shoals#19). |

## Where to read more

In this shell:

- The proof reachability map, integrity discipline, and per-track evidence:
  `research/proof-infra/report.md` (+ `research/proof-infra/RUNBOOK.md`, `runs/`).
- The abstracted derivatives properties: `properties/composites.ch`.
- The real transcendental bodies (fuzz-tier): `references/blackscholes.ch`.
- The oracle backbone (QuantEcon / scipy): `research/proof-infra/oracle/`.
- Upstream blockers and the classification discipline: `docs/UPSTREAM_BUGS.md`.

In the chelis upstream repo (source-of-truth for the load-bearing rows above):

| Topic this shell touches | Upstream location |
|---|---|
| cvc5-lowerable intrinsic set (`exp/sqrt/sin/cos/abs/min/max`; `log` absent) | `crates/chelis-prove/src/tier_b.rs` (`CVC5_LOWERABLE`, `CVC5_TRANSCENDENTAL`) |
| The `log`-has-no-cvc5-term honest boundary (chelis#434) | `crates/chelis-prove/src/tier_b.rs` (`cannot_lower_reason`), `tests/transcendental_finance_lowering.rs` |
| Bundled normal-CDF contract discharge (`erf` abstract subterm) | `crates/chelis-prove/src/contracts.rs` |
| Function-call inlining depth cap | `crates/chelis-prove/src/tier_b_lower.rs` (`MAX_INLINE_DEPTH`) |
| Fuzz-base honesty taxonomy (chelis#435 fix) | chelis#445/#447 (in v0.14.0) |
| Tier B is over the reals (caveat) | `spec/design/chelis_property_spec.md` §Tier B SMT proofs are over the reals |
| `grad` reverse-mode AD, non-diff ops, host vs tensor lane | `spec/06-transformations.md` §2 |
| The downstream shell-repo contract this shell follows | `spec/design/shell_repo_contract.md` §3 |
