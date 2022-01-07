
/*
 * dsub.s
 *
 * Created: 9/17/2021
 *  Author: Tim
 */

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


// 64-bit IEEE floating-point subtract
//
// Entry:
//	r1:r0 = op1
//	r3:r2 = op2
// Exit:
//	r1:r0 = op1 - op2

FUNC_START	__dsub, __aeabi_dsub
	push	{r2, r4-r7, lr}	// must match __dadd
	movs	r4, #1
	lsls	r4, #31
	eors	r3, r4		// invert sign of op2
	b	__dadd_saved

	.endfunc
