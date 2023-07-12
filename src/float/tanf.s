
/*
 * tanf.s
 *
 * Created: 6/22/2023 10:05:24 AM
 *  Author: Tim
 */ 

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


// 32-bit floating-point tangent
//
// Entry:
//	r0 = input angle in radians
// Exit:
//	r0 = tangent
//
// This simply calls __sinf, which return sinf() in r0 and cosf() in r1.
// Tangent is computed by dividing them: tan(x) = sin(x)/cos(x).

FUNC_START	__tanfM0, tanf
	push	{lr}
	bl	__sinfM0
	bl	__fdiv
	pop	{pc}

.endfunc
