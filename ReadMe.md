# Fast, Compact Floating Point Math for ARM Cortex-M0+
### *Now includes float trig functions*
In the first step exanding beyond simple arithmetic, ArmMathM0 now includes
`sinf()`, `cosf()`, `sincosf()`, `tanf()`, `atanf()`, and `atan2f()`.

### Introduction
ArmMathM0 is a ready-to-link library (GNU archive) of floating-point math 
for ARM Cortex-M0 and M0+ that replaces the functions provided by the compiler.
Compared to the math library included with GCC, this library is both faster 
and smaller.

ArmMathM0 includes add, subtract, multiply, divide and square
root for both float and double. It also has float implementations for
`sinf()`, `cosf()`, `sincosf()`, `tanf()`, `atanf()`, and `atan2f()`.
The plan is to build out the float functions (exp, log, etc.) before
implementing these functions for double. The higher functions in the
standard library are built on floating-point arithmetic, so those original 
functions will go faster with ArmMathM0 arithmetic (roughly 2x).

ArmMathM0 has full support for Infinity and NAN, with support for denormal
(tiny) numbers as a compile-time option. It is compatible with the ARM Run-time
ABI, so it simply links in and satisifes compiler calls to floating-point
arithmetic.

### Accuracy
All arithmetic (including square root) provides the exact or closest representable
result. This means the maximum error is 0.5 *unit last place* (ULP) if the exact
answer is at the midpoint between two adjacent representable values.

`sinf()`, `cosf()`, `sincosf()` functions have an error of less than 1 ULP. 
This means when the exact result is between two adjacent representable values, 
it might not choose the closest one. This accuracy is valid for inputs up to ±200 radians.
`tanf()`, computed from sin/cos, has a max error of a little over 2 ULP in that range.
`atanf()`, and `atan2f()` have an error less than 1 ULP over all inputs.

### Build
This project was built with Microchip Studio, and the project files
are included. The build folders **Denormals** and **NoDenormals** have makefiles
and option settings to build their respective versions. The point of the
**NoDenormals** build is to save on code size; there is no performance difference
with normal numbers.
