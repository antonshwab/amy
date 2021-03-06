; Generated from examples/let.amy

; ModuleID = 'amy-module'
source_filename = "<string>"

%MySum = type { i1, i64* }

declare i64 @abs(i64)

define i64 @main() {
entry:
  switch i1 true, label %case.0.0 [
    i1 true, label %case.0.0
    i1 false, label %case.1.0
  ]

case.0.0:                                         ; preds = %entry, %entry
  %0 = call i64 @f(i64 100)
  %1 = call i64 @abs(i64 %0)
  br label %case.end.0

case.1.0:                                         ; preds = %entry
  %2 = call i64 @f(i64 200)
  %3 = call i64 @abs(i64 %2)
  br label %case.end.0

case.end.0:                                       ; preds = %case.1.0, %case.0.0
  %end.0 = phi i64 [ %1, %case.0.0 ], [ %3, %case.1.0 ]
  %4 = add i64 %end.0, 2
  switch i64 %4, label %case.default.6 [
    i64 1, label %case.0.6
  ]

case.default.6:                                   ; preds = %case.end.0
  %5 = sub i64 %4, 3
  br label %case.end.6

case.0.6:                                         ; preds = %case.end.0
  %6 = call i64 @g()
  br label %case.end.6

case.end.6:                                       ; preds = %case.0.6, %case.default.6
  %end.6 = phi i64 [ %5, %case.default.6 ], [ %6, %case.0.6 ]
  switch i64 %end.6, label %case.default.9 [
  ]

case.default.9:                                   ; preds = %case.end.6
  br label %case.end.9

case.end.9:                                       ; preds = %case.default.9
  %end.9 = phi i64 [ %end.6, %case.default.9 ]
  switch i1 false, label %case.0.10 [
    i1 false, label %case.0.10
  ]

case.0.10:                                        ; preds = %case.end.9, %case.end.9
  br label %case.end.10

case.end.10:                                      ; preds = %case.0.10
  %end.10 = phi i64 [ %end.9, %case.0.10 ]
  %7 = call i8 @myEnum()
  switch i8 %7, label %case.0.12 [
    i8 0, label %case.0.12
    i8 1, label %case.1.12
  ]

case.0.12:                                        ; preds = %case.end.10, %case.end.10
  br label %case.end.12

case.1.12:                                        ; preds = %case.end.10
  br label %case.end.12

case.end.12:                                      ; preds = %case.1.12, %case.0.12
  %end.12 = phi i64 [ 1, %case.0.12 ], [ 2, %case.1.12 ]
  %8 = add i64 %end.10, %end.0
  %9 = add i64 %end.12, %8
  ret i64 %9
}

define private i64 @f(i64 %x) {
entry:
  switch i1 true, label %case.0.0 [
    i1 true, label %case.0.0
    i1 false, label %case.1.0
  ]

case.0.0:                                         ; preds = %entry, %entry
  %0 = call i64 @abs(i64 %x)
  br label %case.end.0

case.1.0:                                         ; preds = %entry
  %1 = call i64 @threeHundred()
  br label %case.end.0

case.end.0:                                       ; preds = %case.1.0, %case.0.0
  %end.0 = phi i64 [ %0, %case.0.0 ], [ %1, %case.1.0 ]
  ret i64 %end.0
}

define private i64 @g() {
entry:
  ret i64 1
}

define private i8 @myEnum() {
entry:
  ret i8 1
}

define private %MySum* @mySum() {
entry:
  %0 = alloca %MySum
  %1 = getelementptr %MySum, %MySum* %0, i32 0, i32 0
  store i1 true, i1* %1
  %2 = alloca double
  store double 1.100000e+00, double* %2
  %3 = bitcast double* %2 to i64*
  %4 = getelementptr %MySum, %MySum* %0, i32 0, i32 1
  store i64* %3, i64** %4
  ret %MySum* %0
}

define private i64 @threeHundred() {
entry:
  ret i64 100
}

