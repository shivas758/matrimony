# Razorpay Checkout (razorpay_flutter, SPEC §9.19 B) — the rules Razorpay
# documents for R8 / ProGuard release builds.
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}
-optimizations !method/inlining/
-keepclasseswithmembers class * {
  public void onPayment*(...);
}
