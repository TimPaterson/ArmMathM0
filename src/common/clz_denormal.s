
/*
 * clz_denormal.s
 *
 * Created: 6/23/2021 2:41:16 PM
 *  Author: Tim Paterson
 */ 

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"

	.global	__clz_denormal
	.global	__clz_denormal_ext

//*********************************************************************
// Count Leading Zeros for denormal handling
//
// WARNING!!: This function does not follow the standard
// calling convention!
//
// Entry:
//	r4 = argument to count leading zeros, non-zero
// Exit:
//	r4 = count of leading zeros, 0 - 31
//	r0, r1, r2, r3, r7 preserved
//	r5, r6 destroyed
//*********************************************************************

	.func	__clz_denormal

	.thumb_func
__clz_denormal:
	movs	r5, #31
__clz_denormal_ext:
	CLZ_EXT	r4, r5, r6
	bx	lr

	.endfunc
