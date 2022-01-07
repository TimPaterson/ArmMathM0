# Fast, Compact Floating Point Math for ARM Cortex-M0+
ArmMathM0 is a ready-to-link library (GNU archive) of floating-point math 
for ARM Cortex-M0 and M0+ that replaces the functions provided by the compiler.
Compared to the math library included with GCC, this library is both faster 
and smaller.

At this time, ArmMathM0 includes add, subtract, multiply, divide and square
root for both float and double. The plan is to add the typical transcendental
functions (sin(), exp(). etc.) over time as well. The higher functions in the
standard library are built on floating-point arithmetic, so those original 
functions will go faster with ArmMathM0 arithmetic (roughly 2x).

ArmMathM0 has full support for Infinity and NAN, with support for denormal
(tiny) numbers as a compile-time option. It is compatible with the ARM Run-time
ABI, so it simply links in and satisifes compiler calls to floating-point
arithmetic.

### Build
This project was built with Microchip Studio, and the project files
are included. The build folders **Denormals** and **NoDenormals** have makefiles
and option settings to build their respective versions. The point of the
**NoDenormals** build is to save on code size; there is no performance difference
with normal numbers.

There is also a test driver application designed to communicate through a
serial port. The **Debug** version of this project does not use ArmMathM0 
so performance can be compared.

### Comparison to Qfplib

[Qfplib-M0-full](https://www.quinapalus.com/qfplib-m0-full.html) is a complete,
high-performance math package for ARM Cortex-M0. It includes 
trigonometric, exponential, and logarithm functions and many integer/floating-point
conversion functions not (yet) available in ArmMathM0. The divide and square
root functions in ArmMathM0 were significantly influenced by Qfplib.

In general, there is little difference between Qfplib and ArmMathM0 in 
the speed and size of comparable functions. One minor exception is that subtracting two
numbers that are nearly the same value can slow Qfplib considerably -- more than 5x. 
ArmMathM0 can slow up to 2x in that scenario.

Other differences:

| Feature | ArmMathM0 | QfpLib |
| ------- | --------- | ------ |
| **Organization** | Function per source file | Single source file for all |
| **Usage** | Drop-in AEABI compatible | Rename functions or explicit call |
| **NANs** | Generated and propagated | Converted to Infinity |
| **Denormals** | Optionally supported | Treated as zero |
| **License** | Public domain | GNU GPL 2|
