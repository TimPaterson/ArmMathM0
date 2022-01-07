
/*
 * drsub.s
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


// 64-bit IEEE floating-point subtract reverse
//
// Entry:
//	r1:r0 = op1
//	r3:r2 = op2
// Exit:
//	r1:r0 = op2 - op1

FUNC_START	__drsub, __aeabi_drsub
	push	{r2, r4-r7, lr}	// must match __dadd
	movs	r4, #1
	lsls	r4, #31
	eors	r1, r4		// invert sign of op1
	b	__dadd_saved

	.endfunc
