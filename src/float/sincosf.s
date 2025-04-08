
/*
 * sincosf.s
 *
 * Created: 6/22/2023 9:57:54 AM
 *  Author: Tim
 */ 

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


// 32-bit floating-point sine and cosine
//
// Entry:
//	r0 = input angle in radians
//	r1 = pointer to location to store sin()
//	r2 = pointer to location to store cos()
// Exit:
//	None.
//
// This simply calls __sinf, which return sinf() in r0 and cosf() in r1.

FUNC_START	__sincosfM0, sincosf
	push	{r1, r2, lr}
	bl	__sinfM0
	pop	{r2, r3}
	str	r0, [r2]
	str	r1, [r3]
	pop	{pc}

.endfunc
