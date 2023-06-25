/*
 * TimeTest.h
 *
 * Created: 8/3/2020 2:31:15 PM
 *  Author: Tim
 */ 


#ifndef TIMETEST_H_
#define TIMETEST_H_

#include <stdbool.h>

// Select whether to time tests
//#define TIME_TEST	true
#define TIME_TEST	false

// Test Qfplib
//#define TEST_QFPLIB	true
#define TEST_QFPLIB	false


void ReceiveCase(bool fTime);

//*********************************************************************
// Test case declarations
//*********************************************************************

typedef double FcnDbl2op_t(double op1, double op2);
typedef double FcnDbl1op_t(double op);
typedef float FcnFlt2op_t(float op1, float op2);
typedef float FcnFlt1op_t(float op);

int TimeDbl2op(double op1, double op2, FcnDbl2op_t *pfn, const char *psz);
int TimeFlt2op(float op1, float op2, FcnFlt2op_t *pfn, const char *psz);
int TimeDbl1op(double op, FcnDbl1op_t *pfn, const char *psz);
int TimeFlt1op(float op, FcnFlt1op_t *pfn, const char *psz);

int TimeDbl2opQ(double op1, double op2, FcnDbl2op_t *pfn);
int TimeFlt2opQ(float op1, float op2, FcnFlt2op_t *pfn);
int TimeDbl1opQ(double op, FcnDbl1op_t *pfn);
int TimeFlt1opQ(float op, FcnFlt1op_t *pfn);

double Dbl2opEmpty(double op1, double op2);
double Dbl1opEmpty(double op);
float Flt2opEmpty(float op1, float op2);
float Flt1opEmpty(float op);

//*********************************************************************
// Functions to test
//*********************************************************************

#include "qfplib-full/qfplib-m0-full.h"

float __fadd(float, float);
float __fsub(float, float);
float __frsub(float, float);
float __fmul(float, float);
float __fdiv(float, float);
float __sqrtf(float);

float __aeabi_fadd(float, float);
float __aeabi_fsub(float, float);
float __aeabi_frsub(float, float);
float __aeabi_fmul(float, float);
float __aeabi_fdiv(float, float);

double __dadd(double, double);
double __dsub(double, double);
double __drsub(double, double);
double __dmul(double, double);
double __ddiv(double, double);
double __sqrt(double);

double __aeabi_dadd(double, double);
double __aeabi_dsub(double, double);
double __aeabi_drsub(double, double);
double __aeabi_dmul(double, double);
double __aeabi_ddiv(double, double);

#if	TEST_QFPLIB

#define FADD	qfp_fadd
#define FSUB	qfp_fsub
#define FMUL	qfp_fmul
#define FDIV	qfp_fdiv
#define FSQRT	qfp_fsqrt

#define DADD	qfp_dadd
#define DSUB	qfp_dsub
#define DMUL	qfp_dmul
#define DDIV	qfp_ddiv
#define DSQRT	qfp_dsqrt

#else

#define FADD	__aeabi_fadd
#define FSUB	__aeabi_fsub
#define FMUL	__aeabi_fmul
#define FDIV	__aeabi_fdiv
#define FSQRT	sqrtf

#define DADD	__aeabi_dadd
#define DSUB	__aeabi_dsub
#define DMUL	__aeabi_dmul
#define DDIV	__aeabi_ddiv
#define DSQRT	sqrt

#endif

#endif /* TIMETEST_H_ */