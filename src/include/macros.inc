/*
 * macros.h
 *
 * Created: 6/21/2020 12:28:05 PM
 *  Author: Tim Paterson
 */


//*********************************************************************
// Functions that can optionally be aliased
//*********************************************************************

.macro	DEFINE_ENTRY	local, system
.thumb_set	\system, \local
.endm

.macro	ENTRY_POINT	local, system
	.global	\local
	.thumb_func
\local :
.ifndef	\system
	.global	\system
.thumb_set	\system, \local
.elseif \system == \local
	.global	\system
.endif
.endm

// Same as ENTRY_POINT, but also starts a .func block
.macro	FUNC_START	local, system
	.func	\local
	ENTRY_POINT	\local, \system
.endm

//*********************************************************************
// Register save/restore, depending on NO_DENORMALS
//*********************************************************************

.macro	SAVE_REG	reg:vararg
.ifdef NO_DENORMALS
	push	{ \reg }
.else
	push	{ \reg, lr }
.endif
.endm

.macro	EXIT		reg:vararg
.ifdef NO_DENORMALS
	pop	{ \reg }
	bx	lr
.else
	pop	{ \reg, pc }
.endif
.endm

//*********************************************************************
// 32x32 multiply
//
// You must pass 7 register operands (r0 - r7) as follows:
//
// x - left operand
// y - right operand
// pl - low product, can be same as x
// ph - high product, can be same as y
// t1, t2, t3 - temp registers, trashed
//
// Because x/pl and y/ph can share, a minimum of 5 different registers 
// are required.
//
//*********************************************************************

// unsigned operands
.macro	mul32x32	x, y, pl, ph, t1, t2, t3
	mul32x32signs	\x, \y, \pl, \ph, \t1, \t2, \t3, lsrs, lsrs
.endm

// left operand signed, right unsigned
.macro	mul32sx32	x, y, pl, ph, t1, t2, t3
	mul32x32signs	\x, \y, \pl, \ph, \t1, \t2, \t3, asrs, lsrs
.endm

// left operand unsigned, right signed
.macro	mul32x32s	x, y, pl, ph, t1, t2, t3
	mul32x32signs	\x, \y, \pl, \ph, \t1, \t2, \t3, lsrs, asrs
.endm

// both operands signed
.macro	mul32sx32s	x, y, pl, ph, t1, t2, t3
	mul32x32signs	\x, \y, \pl, \ph, \t1, \t2, \t3, asrs, asrs
.endm

.macro	mul32x32signs	x, y, pl, ph, t1, t2, t3, shrx, shry
	uxth	\t1, \x
	uxth	\t2, \y
	muls	\t1, \t2	// t1 = low product
	\shrx	\t3, \x, #16
	muls	\t2, \t3	// t2 = mid product xh * yl
	\shry	\ph, \y, #16
	muls	\t3, \ph	// t3 = hi product
	uxth	\pl, \x
	muls	\pl, \ph	// pl = mid product xl * yh
	// add pl mid product
	lsls	\ph, \pl, #16
	\shry	\pl, \pl, #16
	adds	\t1, \ph
	adcs	\t3, \pl
	// add t2 mid product
	lsls	\pl, \t2, #16
	\shrx	\ph, \t2, #16
	adds	\pl, \t1
	adcs	\ph, \t3
.endm

//*********************************************************************
// 32x32 multiply, return only hi result
// Doesn't compute lowest product, so can be off by almost 1 bit
// product p can be same as x

.macro	mul32x32hi	x, y, p, t1, t2, t3
	lsrs	\t1, \y, #16	// yH
	uxth	\t2, \x		// xL
	muls	\t2, \t1	// yH * xL = mid 1
	lsrs	\p, \x, #16	// xH
	muls	\t1, \p		// yH * xH = hi
	lsrs	\t3, \t2, #16	// hi half of mid 1
	adds	\t1, \t3
	uxth	\t3, \y		// yL
	muls	\t3, \p		// yL * xH = mid 2
	uxth	\t2, \t2	// lo half of mid1
	adds	\t3, \t2	// sum mids
	lsrs	\t3, #16
	adds	\p, \t1, \t3
.endm

//*********************************************************************
// 64-bit shifts
//*********************************************************************

.macro	lsl64const	lo, hi, cnt, tmp
.if \cnt == 1
	adds	\lo, \lo
	adcs	\hi, \hi
.elseif \cnt == 2
	adds	\lo, \lo
	adcs	\hi, \hi
	adds	\lo, \lo
	adcs	\hi, \hi
.else
	lsls	\hi, #\cnt
	lsrs	\tmp, \lo, #(32 - \cnt)
	orrs	\hi, \tmp
	lsls	\lo, #\cnt
.endif
.endm

.macro	lsr64const	lo, hi, cnt, tmp
	lsrs	\lo, #\cnt
	lsls	\tmp, \hi, #(32 - \cnt)
	orrs	\lo, \tmp
	lsrs	\hi, #\cnt
.endm

.macro	lsl64short	lo, hi, cnt, tmp
	lsls	\hi, \cnt
	movs	\tmp, \lo
	lsls	\lo, \cnt
	subs	\cnt, #32
	negs	\cnt, \cnt
	lsrs	\tmp, \cnt
	orrs	\hi, \tmp
.endm

.macro	lsr64short	lo, hi, cnt, tmp
	lsrs	\lo, \cnt
	movs	\tmp, \hi
	lsrs	\hi, \cnt
	subs	\cnt, #32
	negs	\cnt, \cnt
	lsls	\tmp, \cnt
	orrs	\lo, \tmp
.endm

.macro lsr64	lo, hi, cnt, tmp1, tmp2
	// inspired by __aeabi_llsr
	movs	\tmp1, \hi	// hi1
	movs	\tmp2, \hi	// hi2

	//			cnt < 32		cnt >= 32
	//			--------		---------
	lsrs	\lo, \cnt	// lo >>= cnt		lo = 0
	lsrs	\hi, \cnt	// hi >>= cnt		hi = 0
	subs	\cnt, #32	// cnt1 < 0 (=>big)	0 <= cnt1 < 32
	lsrs	\tmp1, \cnt	// hi1 = 0		hi1 >>= cnt1
	orrs	\lo, \tmp1	// lo1 = lo		lo1 = hi1
	negs	\cnt, \cnt	// cnt2 = 32 - cnt	cnt2 < 0 (=>big)
	lsls	\tmp2, \cnt	// hi2 <<= cnt2		hi2 = 0
	orrs	\lo, \tmp2	// lo1 |= hi2		lo1
.endm

.macro lsl64	lo, hi, cnt, tmp1, tmp2
	movs	\tmp1, \lo	// lo1
	movs	\tmp2, \lo	// lo2

	//			cnt < 32		cnt >= 32
	//			--------		---------
	lsls	\lo, \cnt	// lo <<= cnt		lo = 0
	lsls	\hi, \cnt	// hi <<= cnt		hi = 0
	subs	\cnt, #32	// cnt1 < 0 (=>big)	0 <= cnt1 < 32
	lsls	\tmp1, \cnt	// lo1 = 0		lo1 <<= cnt1
	orrs	\hi, \tmp1	// hi1 = hi		hi1 = lo1
	negs	\cnt, \cnt	// cnt2 = 32 - cnt	cnt2 < 0 (=>big)
	lsrs	\tmp2, \cnt	// lo2 >>= cnt2		lo2 = 0
	orrs	\hi, \tmp2	// hi1 |= lo2		hi1
.endm

//*********************************************************************
// Count leading zeros, you choose the registers to use
//*********************************************************************

// Returns 31 on input of zero.
.macro	CLZ	arg, cnt, tmp
	movs	\cnt, #31
	CLZ_EXT	\arg, \cnt, \tmp
.endm

// You must initialize cnt register to max value
.macro	CLZ_EXT	arg, cnt, tmp
	lsrs	\tmp, \arg, #16
	beq	1f
	movs	\arg, \tmp
	subs	\cnt, #16
1:
	lsrs	\tmp, \arg, #8
	beq	2f
	movs	\arg, \tmp
	subs	\cnt, #8
2:
	lsrs	\tmp, \arg, #4
	beq	3f
	movs	\arg, \tmp
	subs	\cnt, #4
3:
	lsrs	\tmp, \arg, #2
	beq	4f
	movs	\arg, \tmp
	subs	\cnt, #2
4:
	lsrs	\arg, #1
	subs	\arg, \cnt, \arg
.endm
