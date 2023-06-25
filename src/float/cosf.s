
/*
 * cosf.s
 *
 * Created: 6/22/2023 9:52:01 AM
 *  Author: Tim
 */ 

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


// 32-bit floating-point cosine
//
// Entry:
//	r0 = input angle in radians
// Exit:
//	r0 = cosine
//
// This simply calls __sinf, which return sinf() in r0 and cosf() in r1.

FUNC_START	__cosf, cosf
	push	{lr}
	bl	__sinf
	movs	r0, r1
	pop	{pc}

.endfunc
