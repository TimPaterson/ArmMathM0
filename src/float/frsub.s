
/*
 * frsub.s
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


// 32-bit IEEE floating-point subtract reverse
//
// Entry:
//	r0 = op1
//	r1 = op2
// Exit:
//	r0 = op2 - op1

FUNC_START	__frsub, __aeabi_frsub
	movs	r2, #1
	lsls	r2, #31
	eors	r0, r2		// flip sign for subtract
	b	__fadd

	.endfunc
