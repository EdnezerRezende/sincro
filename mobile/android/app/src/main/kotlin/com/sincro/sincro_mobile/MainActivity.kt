package com.sincro.sincro_mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (e não FlutterActivity) porque o plugin `health` pede as permissões do
// Health Connect via registerForActivityResult, que exige uma ComponentActivity/FragmentActivity.
class MainActivity : FlutterFragmentActivity()
