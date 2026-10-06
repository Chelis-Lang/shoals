<!-- BEGIN CHELIS MANAGED BLOCK: chelis-surface chelis@0.19.0 (sha256:1c5cb79cd021938f) -->
# Chelis capability surface

This guide maps language operations, compiler support, and bundled `chelis-std`.
The numbered specs decide language behavior; code and executable tests establish
which parts the compiler implements. `chelis reef conform sync` copies this
guide into every shell's `docs/CHELIS_SURFACE.md`
([`spec/design/shell_repo_contract.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/design/shell_repo_contract.md) §3),
so a shell reads the guide of the release it pins.

This page describes the source tree it ships with: `main` in the compiler
repository, and the pinned release in a shell's copy. Relative paths and links
name files in [`Chelis-Lang/chelis`](https://github.com/Chelis-Lang/chelis).
Language rules, registered builtins, and target execution support have
separate owners, identified below.

If this guide disagrees with an owning source, correct the guide:

| Surface | Source of truth |
|---|---|
| Language operations and adjoints | [`spec/05-risc-primitives.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/05-risc-primitives.md), [`spec/06-transformations.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/06-transformations.md) |
| Syntax, types, dtypes and effects | [`spec/02-surf-syntax.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/02-surf-syntax.md), [`spec/04-type-system.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/04-type-system.md) |
| Builtin registration | `BUILTIN_NAMES` and `builtin_env`, `crates/chelis-types/src/builtins.rs` |
| IR and target implementation | `RiscOp`, `crates/chelis-ir/src/dag.rs`; `crates/chelis-compiler-api/src/compiler.rs`; `crates/chelis-backend-{c,hip,metal}` |
| Target contract | [`spec/08-backends.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/08-backends.md) and the dtype matrix in `spec/04` §1.1.3 |
| Command surface | `crates/chelis-cli/src/main.rs` and its CLI integration tests |
| Scope taxonomy (core vs std vs shell) | [`spec/design/chelis_canonical_reference.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/design/chelis_canonical_reference.md) §8.5 |

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

The [`explicit_normalization.ch`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/examples/explicit_normalization.ch)
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
[`list_shared_extent.ch`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/examples/list_shared_extent.ch).
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

The executable [directory listing example](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/examples/io/list_directory.ch)
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
[`spec/design/differentiable_language.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/design/differentiable_language.md)
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
[`manual_gates.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/docs/manual_gates.md#compiler-feature-acceptance-gates).

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
- **Ownership:** tensor values are owned by default. An owned tensor passed
  to an `&tensor` parameter auto-borrows and leaves the owner live. A borrowed
  `&tensor` passed to an owned tensor parameter is rejected unless the program
  writes `copy(x)` to create a separate owner. Ordinary consuming fan-out of
  an owned tensor may receive compiler-inserted copies; `drop` is terminal and
  `realize` consumes. `len`/`index` auto-borrow their List/Dict query argument.
  Key-carrying values are affine and cannot be copied or borrowed. The
  ownership pass carries borrow, move, clone, and drop obligations into
  verified lowering.
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
| `migrate` | Explicit `surf`/`deep` source migrations, plus `pipes --baseline-compiler OLD` with whole-file Deep proof; pipe migration defaults to an atomic batch, with explicit `--keep-going` for independent files and a nonzero exit on any failure | command-specific |
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
[`spec/design/chelis_property_spec.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/design/chelis_property_spec.md);
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
| [`spec/02-surf-syntax.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/02-surf-syntax.md), [`spec/03-deep-syntax.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/03-deep-syntax.md) | source syntax, canonical Surf/Deep conversion, and metadata |
| [`spec/04-type-system.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/04-type-system.md) | dtypes, shapes, accumulators, effects, and linearity |
| [`spec/05-risc-primitives.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/05-risc-primitives.md) | operation signatures, traps, and adjoints |
| [`spec/06-transformations.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/06-transformations.md) | `grad`, `vmap`, and `jit` semantics |
| [`spec/08-backends.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/08-backends.md) | backend strategy and target constraints |
| [`spec/design/differentiable_language.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/design/differentiable_language.md) | implementation sequence for broader AD |
| [`spec/design/rank_polymorphism.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/design/rank_polymorphism.md) | rank-polymorphic implementation |
| [`spec/design/implicit_linearity.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/design/implicit_linearity.md) | ownership implementation |
| [`spec/design/chelis_canonical_reference.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/design/chelis_canonical_reference.md) | core, stdlib, and shell boundary |
| [`spec/design/shell_repo_contract.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.0/spec/design/shell_repo_contract.md) | a downstream shell's required surface view |

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

The compiler and dependency versions are declared in [`reef.toml`](../reef.toml).
The installed artifact hashes are recorded in `reef.lock` when Reef resolves
the published releases.

What the Chelis language and the bundled chelis-std actually provide to the
quantitative-finance domain this shell touches — numerical methods, pricing,
Greeks, and the proof surface over them. **Read this before designing around a
suspected language gap.**

Rows marked `@pin` describe capabilities in the pinned toolchain; `@upstream`
marks capabilities unavailable at this pin. Refresh this table at every pin bump
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
| SMT proof tier (cvc5) in the release tarball | `@pin` | Tier B lowers to cvc5 over the reals (`QF_NRA`, or `QF_NRAT` when a transcendental is present). A proven result is a real-arithmetic fact, not an IEEE-`f32` statement; the result carries `arith_model:"real"`. |
| Transcendentals `exp`, `sqrt`, `sin`, `cos` lower to SMT | `@pin*` | These four **do** lower — cvc5 kinds `EXPONENTIAL`/`SQRT`/`SINE`/`COSINE`, selecting the `QF_NRAT` logic. *`QF_NRAT` is **incomplete**: cvc5 may return `unknown`, which chelis records as `unsupported` (solver capacity) and `--tier auto` degrades **honestly** to fuzz — never a false proven. Keep structural greens transcendental-free by construction where possible (report §3). |
| Certified-envelope transcendental discharge (`erf`/`normal_cdf`/`exp`/`log`/`sqrt` subterms) | `@pin` | A soundly boundable transcendental subterm is abstracted to a fresh variable over its certified envelope hull; the result identifies `proven_modulo_certified_envelope` as its proof tier. Unboundable arguments fail closed. Goals that depend on coupling between abstractions remain at `fuzz_validated` or deferred under chelis#637; see `UPSTREAM_BUGS.md`. |
| `normal_cdf` contracts | `@pin` | `Std.Contracts.normal_cdf` calls the pinned `standard_normal_cdf` graph. Its range contract validates at f32 and supports the structural upper-bound and delta invariants. The reflection contract fails its fixed 1e-10 tolerance at f32 (chelis#3116), so Shoals defers the put-call parity invariant that depends on it. |
| Algebraic `abs`, `min`, `max` lower to SMT | `@pin` | In `CVC5_LOWERABLE`, `QF_NRA` (algebraic, not transcendental). `min`/`max` lower to ITE. |
| Composite derivatives greens | `@pin` | The upper-bound and delta properties in `properties/composites.ch` prove their structure at the SMT tier using the separately validated normal-CDF range contract. Their `proven_modulo_fuzz_validated_contract` verdict is classified from `proof_tier` and qualifiers. The reflection-dependent parity property is deferred under chelis#3116. |
| Economic / dynamic-programming greens | `@pin` | Markov simplex preservation, Bellman monotonicity/boundedness/contraction, PV/Gordon positivity & monotonicity discharge at SMT with **no** transcendental contract (report §6). Structurally more complete than a derivatives green. |
| Function-call inlining depth for SMT | `@pin` | Nested calls inline to `MAX_INLINE_DEPTH = 3` (`chelis-prove/src/tier_b_lower.rs`); deeper chains route to Tier C. No shoals goal hits this today; c-note probe `p07` pending (`UPSTREAM_BUGS.md`). |
| Beacon (large-scale concrete verification) | `@upstream` | `beacon_available=false` in the release binary; gated on `CHELIS_BEACON_BIN`. Shoals provides the real-pricer `bs_call_wire_f64` tensor root (shoals#19); bounded-domain consumption remains Beacon#74. |
| prove-side import resolution | `@pin` | `prove` resolves package imports, so a property targets the real exported function; standalone structural probes are self-contained (report §2). |
| Constraint-directed property sampling | `@pin` | Shoals#37 requires 25 accepted samples at each of seeds 0, 1, and 2 for both parametric and historical risk families; a starved or partially accepted run fails the gate. |
| Linked Nautilus quantile contract identity | `@pin` | The `std.quantile.monotonicity` contract binds only to the linker-owned `Nautilus.Stats.quantile_vec` (chelis#979). Shoals keeps wrapper claims at the observed `fuzz_validated` proof tier and never reconstructs the wrapper relation from source text. |

## Numeric & language primitives the domain uses

| Family | Status | Notes |
|---|---|---|
| Arithmetic `+ - * /`, comparisons | `@pin` | Lower to cvc5. Keep `/` out of SMT goals where possible; use multiplied-through polynomial form. |
| `if/then/else` | `@pin` | Lowers as ITE in `QF_NRA`. |
| `Option[T]`, `Some`/`None`, `match`; `@opaque` + `@invariant` | `@pin` | Opaque-invariant abstraction is the path from synthetic green to a green a quant recognizes (report §1, §3); producer obligations discharge at SMT. |
| `Std.Test` (`assert_close`, `assert_eq`) | `@pin` | The executable numeric suites under `tests/` and `tests-manual/` use polymorphic `assert_eq[q](actual, expected, label)` and `assert_close[p_float]`. Tensor close tolerances have the tensor's dtype. |
| WireDag lowering (`chelis tide serve` `/lower`) | `@pin` | `scripts/validate_bs_wire_root.py` checks the `bs_call_wire_f64` receipt, structural validity, and two independent cold lowerings. |
| `count` ([05-OP-29]), direct `sub` / `min_elem` ([05-OP-40]/[05-OP-41]) | `@pin` | Available; Shoals does not depend on them. |
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
| `erf64` | Chelis's correctly rounded `erf` builtin | **>= 5.5177e-17** (~0.25 ulp of 1.0) | worst observed at x = -1.25 over 531 compiled samples at 60 dps |
| `n_cdf64` | Chelis's `standard_normal_cdf` graph over correctly rounded `erfc` | **>= 7.7516e-17** (~0.35 ulp of 1.0) | worst observed near x = 1.0 over the same compiled samples at 60 dps; the separate relative leg checks the negative tail |

`n_cdf64` delegates to Chelis's `standard_normal_cdf`, whose graph uses
correctly rounded `erfc` directly for the negative tail. The oracle checks
relative error at thirteen points from -6 down to **-37**, against a 60-digit
reference, with a limit of 1e-12. This catches a return to `1 - erf`
cancellation that the absolute sweep cannot see (shoals#68).

The sweep reaches -37 because shoals#68's failure mode was early **saturation**,
and five points clustered at -6 to -9 pin that issue's table without covering
the class: the pre-#136 kernel's silent-zero band began at x = -8.485, and a
regression saturating anywhere further out would have passed unnoticed.
Measured at this pin, `standard_normal_cdf` stays under **one ulp** across the
range -- worst observed 2.17e-16 (0.977 ulp) at x = -26.95 over a 631-point
scan, about four orders inside the limit, and under 9.4e-17 at the thirteen
swept points themselves. Those are grid maxima, not proofs. It stops at -37 rather than
-37.5 because past that the **result** runs out of room rather than the kernel
being wrong -- the true value leaves the normal doubles between -37.5 and -37.6,
and relative error reaches 3.1e-9 at -38.0 and 4.8e-2 at -38.4 before the call
returns `0.0` from about -38.5. Below -37 is therefore unguarded on purpose: the
boundary belongs to the f64 subnormal range and the Chelis builtin, not to
Shoals, so re-measure before extending it.

**No bound is stated for the Greeks.** The error of a derivative is not
controlled by the error of the function — in Black–Scholes the true
`S·φ(d1) − K'·φ(d2)` terms cancel exactly, while rounded intermediates may
leave a residue amplified by `√T/σ` or `1/(Sσ√T)`. The table above measures
scalar functions, not derivatives over the Greek parameter space.

Shoals's scalar `erf64` is a compatibility wrapper over Chelis's `erf`, and
`n_cdf64` delegates to `standard_normal_cdf`. `Shoals.Greeks`,
`Shoals.PricingExtended`, and the reference modules call Chelis's `erfc`
directly. Their f32 arithmetic still has its own rounding effects.

The separate `bs_call_wire_f64` path retains caller-supplied A&S coefficients
as part of its published WireDag input contract. It is checked against the
scalar pricer with a scale-aware tolerance, not exact equality. The dated
research projects under `research/proof-infra/` retain their own historical
A&S bodies and do not define the current package pricing API.

## Automatic differentiation (`grad`) — the Greek-set surface

| Capability | Status | Notes |
|---|---|---|
| `grad` reverse-mode AD in `eval` / host runtime | `@pin` | The first-order call Greek exports differentiate the Black–Scholes and normal-CDF body; the result must be a floating scalar. `scripts/oracle_greeks_gate.py` checks their values. |
| `grad(grad(...))` second order | `@pin` | Gamma, volga, and vanna use nested `grad` through the Black–Scholes price body. The scalar kernel keeps sequential conditionals while chelis#2825 remains open; `tests-manual/greeks_secondorder.ch` and the Greek oracle check the outputs. |
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
