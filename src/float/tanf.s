
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
.include "trigf.inc"


//****************************************************************************
// 32-bit floating-point tangent
//
// Entry:
//	r0 = input angle in radians
// Exit:
//	r0 = tangent
//
// This simply calls __sincosf_calc, which return sinf() in r0 and cosf() in r1.
// Tangent is computed by dividing them: tan(x) = sin(x)/cos(x).
//****************************************************************************


FUNC_START	__tanfM0, tanf
	push	{r4-r7, lr}
	lsls	r1, r0, #1		// clear input sign
	lsrs	r1, #MANT_BITS32 + 1	// isolate exponent
	cmp	r1, #SINE_MAX_VALID_EXP + EXP_BIAS32
	bgt	BigExp
	cmp	r1, #COS_X_EQUALS_1_EXP + EXP_BIAS32
	blt	ReturnOp		// result = argument

	// r0 = input angle in radians
	// r1 = biased exponent e, COS_X_EQUALS_1_EXP < e < SINE_MAX_VALID_EXP

	bl	__sincosf_calc

	// r0 = sine p31
	// r1 = cosine p31
	// r4 = -exponent of sine
	// r5 = -exponent of cosine
	// r6 = octant info

	// Bits 0-2: octant number
	//  octant  |  swap | sin | cos | tan
	//     0    |    no |  +  |  +	|  +
	//     1    |   yes |  +  |  +	|  +
	//     2    |   yes |  +  |  -	|  -
	//     3    |    no |  +  |  -	|  -
	//     4    |    no |  -  |  -	|  +
	//     5    |   yes |  -  |  -	|  +
	//     6    |   yes |  -  |  +	|  -
	//     7    |    no |  -  |  +	|  -
	//		  ^    ^     ^	   ^
	// (octant+1) & 2 |    |     |	   |
	//	    octant & 4 |     |	   |
	//	      (octant+2) & 4 |	   |
	//			octant & 2 |

	subs	r5, r4		// exponent difference after divide
	// check whether to swap sin/cos
	adds	r3, r6, 1	// add to octant bit 0
	lsrs	r3, #2		// octant bit 1 to CY
	bcc	1f
	SWAP	r0, r1		// use cos instead of sin
	negs	r5, r5
1:
	lsrs	r0, #1		// add leading zero so it's positive
	lsrs	r1, #1
	bl	__fixed_dividef
NormLoop:
	subs	r5, #1
	adds	r0, r0
	bcc	NormLoop
	adds	r5, EXP_BIAS32 + 1
	lsrs	r6, #1		// isolate octant bit 1
	lsls	r6, #31		// sign bit
	lsls	r5, #MANT_BITS32// position exponent
	lsrs	r0, #EXP_BITS32 + 1	// position mantissa
	adcs	r0, r5		// combine exponent and rounding bit
	orrs	r0, r6		// include sign
	pop	{r4-r7, pc}

BigExp:
	cmp	r1, #EXP_SPECIAL32
	bne	ReturnNan	// Huge, can't do it, return NAN
	// If argument is NAN, return it. If it's infinity, make a new NAN.
	lsls	r2, r0, #(EXP_BITS32 + 1)	// mantissa == 0?
	bne	ReturnOp	// input is NAN, return it
ReturnNan:
	MOV_IMM	r0, NAN32
ReturnOp:
	pop	{r4-r7, pc}

.endfunc
