# Third-party notices

StillOpen first-party code and tests use the root MIT license. Third-party materials retain their own licenses and copyright notices; the root license does not relicense them.

The pinned Gradle 9.1.0 wrapper comes from `https://github.com/gradle/gradle/tree/v9.1.0`; see `third_party/gradle/LICENSE` (Apache-2.0 and included-component terms). Wrapper and distribution checksums are verified/pinned. Flutter-generated host/project scaffolding is subject to the Flutter license reproduced in `third_party/flutter/LICENSE`, from Flutter revision `924134a44c189315be2148659913dda1671cbe99`.

Fresh locked resolution identified 107 Dart/SDK dependencies; full license texts are preserved under `third_party/dart/<package>/LICENSE`. This inventory includes development and unused-platform transitives. Dependency license texts and native reference metadata were inspected. Native dependencies are resolved by Gradle at build time; no dependency source, engine libraries or app binaries are bundled in this source release. Their licenses remain separate; anyone distributing binaries must review the resulting binary and its notices/source obligations. MPL-marked `dbus` requires separate treatment if its source or a binary containing it is distributed. No dependency source is relicensed as MIT.

## Resolved Dart packages

| Package | Version | Observed license markers |
| --- | --- | --- |
| args | 2.7.0 | BSD |
| async | 2.13.1 | BSD |
| boolean_selector | 2.1.2 | BSD |
| characters | 1.4.1 | BSD |
| clock | 1.1.2 | Apache-2.0 |
| code_assets | 1.2.0 | BSD |
| collection | 1.19.1 | BSD |
| cross_file | 0.3.5+2 | BSD |
| crypto | 3.0.7 | BSD |
| cupertino_icons | 1.0.9 | MIT |
| dbus | 0.7.12 | MPL-2.0 |
| fake_async | 1.3.3 | Apache-2.0 |
| ffi | 2.2.0 | BSD |
| ffi_leak_tracker | 0.1.2 | BSD |
| file | 7.0.1 | BSD |
| file_selector | 1.1.0 | BSD |
| file_selector_android | 0.5.2+6 | Apache-2.0, BSD |
| file_selector_ios | 0.5.3+5 | BSD |
| file_selector_linux | 0.9.4 | BSD |
| file_selector_macos | 0.9.5 | BSD |
| file_selector_platform_interface | 2.7.0 | BSD |
| file_selector_web | 0.9.4+2 | BSD |
| file_selector_windows | 0.9.3+5 | BSD |
| fixnum | 1.1.1 | BSD |
| flutter | Flutter SDK 3.44.1 | BSD |
| flutter_driver | Flutter SDK 3.44.1 | BSD |
| flutter_lints | 6.0.0 | BSD |
| flutter_local_notifications | 21.0.0 | BSD |
| flutter_local_notifications_linux | 8.0.0 | BSD |
| flutter_local_notifications_platform_interface | 11.0.0 | BSD |
| flutter_local_notifications_windows | 3.0.0 | BSD |
| flutter_plugin_android_lifecycle | 2.0.34 | BSD |
| flutter_test | Flutter SDK 3.44.1 | BSD |
| flutter_web_plugins | Flutter SDK 3.44.1 | BSD |
| fuchsia_remote_debug_protocol | Flutter SDK 3.44.1 | BSD |
| hooks | 2.0.0 | BSD |
| http | 1.6.0 | BSD |
| http_parser | 4.1.2 | BSD |
| image_picker | 1.2.2 | Apache-2.0, BSD |
| image_picker_android | 0.8.13+17 | Apache-2.0, BSD |
| image_picker_for_web | 3.1.1 | BSD |
| image_picker_ios | 0.8.13+6 | Apache-2.0, BSD |
| image_picker_linux | 0.2.2 | BSD |
| image_picker_macos | 0.2.2+1 | BSD |
| image_picker_platform_interface | 2.11.1 | BSD |
| image_picker_windows | 0.2.2 | BSD |
| integration_test | Flutter SDK 3.44.1 | BSD |
| jni | 1.0.0 | BSD |
| jni_flutter | 1.0.1 | BSD |
| leak_tracker | 11.0.2 | BSD |
| leak_tracker_flutter_testing | 3.0.10 | BSD |
| leak_tracker_testing | 3.0.2 | BSD |
| lints | 6.1.0 | BSD |
| logging | 1.3.0 | BSD |
| matcher | 0.12.19 | BSD |
| material_color_utilities | 0.13.0 | Apache-2.0 |
| meta | 1.18.0 | BSD |
| mime | 2.0.0 | BSD |
| objective_c | 9.4.1 | BSD |
| open_filex | 4.7.0 | BSD |
| package_config | 2.2.0 | BSD |
| path | 1.9.1 | BSD |
| path_provider | 2.1.5 | BSD |
| path_provider_android | 2.3.1 | BSD |
| path_provider_foundation | 2.6.0 | BSD |
| path_provider_linux | 2.2.1 | BSD |
| path_provider_platform_interface | 2.1.2 | BSD |
| path_provider_windows | 2.3.0 | BSD |
| petitparser | 7.0.2 | MIT |
| platform | 3.1.6 | BSD |
| plugin_platform_interface | 2.1.8 | BSD |
| process | 5.0.6 | BSD |
| pub_semver | 2.2.0 | BSD |
| receive_sharing_intent | 1.8.1 | Apache-2.0 |
| record_use | 0.6.0 | BSD |
| share_plus | 13.1.0 | BSD |
| share_plus_platform_interface | 7.1.0 | BSD |
| shared_preferences | 2.5.5 | BSD |
| shared_preferences_android | 2.4.23 | BSD |
| shared_preferences_foundation | 2.5.6 | BSD |
| shared_preferences_linux | 2.4.1 | BSD |
| shared_preferences_platform_interface | 2.4.2 | BSD |
| shared_preferences_web | 2.4.3 | BSD |
| shared_preferences_windows | 2.4.1 | BSD |
| sky_engine | Flutter SDK 3.44.1 | MPL-2.0, Apache-2.0, MIT, BSD |
| source_span | 1.10.2 | BSD |
| stack_trace | 1.12.1 | BSD |
| stream_channel | 2.1.4 | BSD |
| string_scanner | 1.4.1 | BSD |
| sync_http | 0.3.1 | BSD |
| term_glyph | 1.2.2 | BSD |
| test_api | 0.7.11 | BSD |
| timezone | 0.11.0 | BSD |
| typed_data | 1.4.0 | BSD |
| url_launcher_linux | 3.2.2 | BSD |
| url_launcher_platform_interface | 2.3.2 | BSD |
| url_launcher_web | 2.4.3 | BSD |
| url_launcher_windows | 3.1.5 | BSD |
| uuid | 4.5.3 | MIT |
| vector_math | 2.2.0 | BSD |
| vm_service | 15.2.0 | BSD |
| web | 1.1.1 | BSD |
| webdriver | 3.2.0 | Apache-2.0 |
| win32 | 6.3.0 | BSD |
| xdg_directories | 1.1.0 | BSD |
| xml | 6.6.1 | MIT |
| yaml | 3.1.3 | MIT |

## Native Android dependency references

The table covers the 117 resolved debug runtime coordinates of the validated build, including development/test libraries. Missing child-POM declarations were resolved via official Maven parent POMs or the pinned Flutter engine/framework notices. These are dependency references, not bundled code or binaries. `third_party/native/` preserves additional upstream license texts; `third_party/dart/sky_engine/LICENSE` preserves the Flutter engine component notices.

| Coordinate | Declared or inherited terms |
| --- | --- |
| `androidx.activity:activity:1.12.4` | The Apache Software License, Version 2.0 |
| `androidx.activity:activity-ktx:1.12.4` | The Apache Software License, Version 2.0 |
| `androidx.annotation:annotation:1.9.1` | The Apache Software License, Version 2.0 |
| `androidx.annotation:annotation-experimental:1.4.1` | The Apache Software License, Version 2.0 |
| `androidx.annotation:annotation-jvm:1.9.1` | The Apache Software License, Version 2.0 |
| `androidx.appcompat:appcompat:1.6.1` | The Apache Software License, Version 2.0 |
| `androidx.appcompat:appcompat-resources:1.6.1` | The Apache Software License, Version 2.0 |
| `androidx.arch.core:core-common:2.2.0` | The Apache Software License, Version 2.0 |
| `androidx.arch.core:core-runtime:2.2.0` | The Apache Software License, Version 2.0 |
| `androidx.asynclayoutinflater:asynclayoutinflater:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.collection:collection:1.4.2` | The Apache Software License, Version 2.0 |
| `androidx.collection:collection-jvm:1.4.2` | The Apache Software License, Version 2.0 |
| `androidx.collection:collection-ktx:1.4.2` | The Apache Software License, Version 2.0 |
| `androidx.compose.runtime:runtime-annotation:1.9.0` | The Apache Software License, Version 2.0 |
| `androidx.compose.runtime:runtime-annotation-android:1.9.0` | The Apache Software License, Version 2.0 |
| `androidx.concurrent:concurrent-futures:1.1.0` | The Apache Software License, Version 2.0 |
| `androidx.coordinatorlayout:coordinatorlayout:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.core:core:1.18.0` | The Apache Software License, Version 2.0 |
| `androidx.core:core-ktx:1.18.0` | The Apache Software License, Version 2.0 |
| `androidx.core:core-viewtree:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.cursoradapter:cursoradapter:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.customview:customview:1.1.0` | The Apache Software License, Version 2.0 |
| `androidx.datastore:datastore:1.1.7` | The Apache Software License, Version 2.0 |
| `androidx.datastore:datastore-android:1.1.7` | The Apache Software License, Version 2.0 |
| `androidx.datastore:datastore-core:1.1.7` | The Apache Software License, Version 2.0 |
| `androidx.datastore:datastore-core-android:1.1.7` | The Apache Software License, Version 2.0 |
| `androidx.datastore:datastore-core-okio:1.1.7` | The Apache Software License, Version 2.0 |
| `androidx.datastore:datastore-core-okio-jvm:1.1.7` | The Apache Software License, Version 2.0 |
| `androidx.datastore:datastore-preferences:1.1.7` | The Apache Software License, Version 2.0 |
| `androidx.datastore:datastore-preferences-android:1.1.7` | The Apache Software License, Version 2.0 |
| `androidx.datastore:datastore-preferences-core:1.1.7` | The Apache Software License, Version 2.0 |
| `androidx.datastore:datastore-preferences-core-android:1.1.7` | The Apache Software License, Version 2.0 |
| `androidx.datastore:datastore-preferences-external-protobuf:1.1.7` | BSD-3-Clause |
| `androidx.datastore:datastore-preferences-proto:1.1.7` | The Apache Software License, Version 2.0 |
| `androidx.documentfile:documentfile:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.drawerlayout:drawerlayout:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.emoji2:emoji2:1.2.0` | The Apache Software License, Version 2.0 |
| `androidx.emoji2:emoji2-views-helper:1.2.0` | The Apache Software License, Version 2.0 |
| `androidx.exifinterface:exifinterface:1.4.2` | The Apache Software License, Version 2.0 |
| `androidx.fragment:fragment:1.7.1` | The Apache Software License, Version 2.0 |
| `androidx.fragment:fragment-ktx:1.7.1` | The Apache Software License, Version 2.0 |
| `androidx.interpolator:interpolator:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.legacy:legacy-support-core-ui:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.legacy:legacy-support-core-utils:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.lifecycle:lifecycle-common:2.7.0` | The Apache Software License, Version 2.0 |
| `androidx.lifecycle:lifecycle-common-java8:2.7.0` | The Apache Software License, Version 2.0 |
| `androidx.lifecycle:lifecycle-livedata:2.7.0` | The Apache Software License, Version 2.0 |
| `androidx.lifecycle:lifecycle-livedata-core:2.7.0` | The Apache Software License, Version 2.0 |
| `androidx.lifecycle:lifecycle-livedata-core-ktx:2.7.0` | The Apache Software License, Version 2.0 |
| `androidx.lifecycle:lifecycle-process:2.7.0` | The Apache Software License, Version 2.0 |
| `androidx.lifecycle:lifecycle-runtime:2.7.0` | The Apache Software License, Version 2.0 |
| `androidx.lifecycle:lifecycle-runtime-ktx:2.7.0` | The Apache Software License, Version 2.0 |
| `androidx.lifecycle:lifecycle-viewmodel:2.7.0` | The Apache Software License, Version 2.0 |
| `androidx.lifecycle:lifecycle-viewmodel-ktx:2.7.0` | The Apache Software License, Version 2.0 |
| `androidx.lifecycle:lifecycle-viewmodel-savedstate:2.7.0` | The Apache Software License, Version 2.0 |
| `androidx.loader:loader:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.localbroadcastmanager:localbroadcastmanager:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.media:media:1.1.0` | The Apache Software License, Version 2.0 |
| `androidx.navigationevent:navigationevent:1.0.2` | The Apache Software License, Version 2.0 |
| `androidx.navigationevent:navigationevent-android:1.0.2` | The Apache Software License, Version 2.0 |
| `androidx.preference:preference:1.2.1` | The Apache Software License, Version 2.0 |
| `androidx.print:print:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.profileinstaller:profileinstaller:1.4.0` | The Apache Software License, Version 2.0 |
| `androidx.recyclerview:recyclerview:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.resourceinspection:resourceinspection-annotation:1.0.1` | The Apache Software License, Version 2.0 |
| `androidx.savedstate:savedstate:1.2.1` | The Apache Software License, Version 2.0 |
| `androidx.savedstate:savedstate-ktx:1.2.1` | The Apache Software License, Version 2.0 |
| `androidx.slidingpanelayout:slidingpanelayout:1.2.0` | The Apache Software License, Version 2.0 |
| `androidx.startup:startup-runtime:1.1.1` | The Apache Software License, Version 2.0 |
| `androidx.swiperefreshlayout:swiperefreshlayout:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.test:monitor:1.3.0` | The Apache Software License, Version 2.0 |
| `androidx.test:rules:1.2.0` | The Apache Software License, Version 2.0 |
| `androidx.test:runner:1.3.0` | The Apache Software License, Version 2.0 |
| `androidx.test.espresso:espresso-core:3.3.0` | The Apache Software License, Version 2.0 |
| `androidx.test.espresso:espresso-idling-resource:3.3.0` | The Apache Software License, Version 2.0 |
| `androidx.tracing:tracing:1.2.0` | The Apache Software License, Version 2.0 |
| `androidx.transition:transition:1.4.1` | The Apache Software License, Version 2.0 |
| `androidx.vectordrawable:vectordrawable:1.1.0` | The Apache Software License, Version 2.0 |
| `androidx.vectordrawable:vectordrawable-animated:1.1.0` | The Apache Software License, Version 2.0 |
| `androidx.versionedparcelable:versionedparcelable:1.1.1` | The Apache Software License, Version 2.0 |
| `androidx.viewpager:viewpager:1.0.0` | The Apache Software License, Version 2.0 |
| `androidx.window:window:1.2.0` | The Apache Software License, Version 2.0 |
| `androidx.window:window-java:1.2.0` | The Apache Software License, Version 2.0 |
| `androidx.window.extensions.core:core:1.0.0` | The Apache Software License, Version 2.0 |
| `com.getkeepsafe.relinker:relinker:1.4.5` | The Apache Software License, Version 2.0 |
| `com.google.code.findbugs:jsr305:3.0.2` | The Apache Software License, Version 2.0 |
| `com.google.code.gson:gson:2.12.0` | Apache-2.0 |
| `com.google.errorprone:error_prone_annotations:2.36.0` | Apache 2.0 |
| `com.google.guava:failureaccess:1.0.1` | The Apache Software License, Version 2.0 |
| `com.google.guava:guava:28.1-android` | Apache License, Version 2.0 |
| `com.google.guava:listenablefuture:9999.0-empty-to-avoid-conflict-with-guava` | The Apache Software License, Version 2.0 |
| `com.google.j2objc:j2objc-annotations:1.3` | The Apache Software License, Version 2.0 |
| `com.squareup:javawriter:2.1.1` | Apache 2.0 |
| `com.squareup.okio:okio:3.4.0` | The Apache Software License, Version 2.0 |
| `com.squareup.okio:okio-jvm:3.4.0` | The Apache Software License, Version 2.0 |
| `io.flutter:arm64_v8a_debug:1.0.0-c416acfeb8126e097f758c664aaa3da929e27da0` | BSD-3-Clause with separately licensed engine components |
| `io.flutter:armeabi_v7a_debug:1.0.0-c416acfeb8126e097f758c664aaa3da929e27da0` | BSD-3-Clause with separately licensed engine components |
| `io.flutter:flutter_embedding_debug:1.0.0-c416acfeb8126e097f758c664aaa3da929e27da0` | BSD-3-Clause with separately licensed engine components |
| `io.flutter:x86_64_debug:1.0.0-c416acfeb8126e097f758c664aaa3da929e27da0` | BSD-3-Clause with separately licensed engine components |
| `javax.inject:javax.inject:1` | The Apache Software License, Version 2.0 |
| `junit:junit:4.12` | Eclipse Public License 1.0 |
| `org.checkerframework:checker-compat-qual:2.5.5` | GNU General Public License, version 2 (GPL2), with the classpath exception; The MIT License |
| `org.codehaus.mojo:animal-sniffer-annotations:1.18` | MIT license |
| `org.hamcrest:hamcrest-core:1.3` | New BSD License |
| `org.hamcrest:hamcrest-integration:1.3` | New BSD License |
| `org.hamcrest:hamcrest-library:1.3` | New BSD License |
| `org.jetbrains:annotations:23.0.0` | The Apache Software License, Version 2.0 |
| `org.jetbrains.kotlin:kotlin-android-extensions-runtime:1.9.22` | The Apache License, Version 2.0 |
| `org.jetbrains.kotlin:kotlin-parcelize-runtime:1.9.22` | The Apache License, Version 2.0 |
| `org.jetbrains.kotlin:kotlin-stdlib:2.3.20` | Apache-2.0 |
| `org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.8.0` | The Apache License, Version 2.0 |
| `org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.8.0` | The Apache License, Version 2.0 |
| `org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0` | The Apache Software License, Version 2.0 |
| `org.jetbrains.kotlinx:kotlinx-coroutines-bom:1.9.0` | The Apache Software License, Version 2.0 |
| `org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0` | The Apache Software License, Version 2.0 |
| `org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm:1.9.0` | The Apache Software License, Version 2.0 |
| `org.jspecify:jspecify:1.0.0` | The Apache License, Version 2.0 |

Guava references: [Apache license at v28.1](https://github.com/google/guava/blob/v28.1/COPYING). Hamcrest 1.3: [BSD license](https://github.com/hamcrest/JavaHamcrest/blob/hamcrest-java-1.3/LICENSE.txt). Animal Sniffer 1.18: [upstream MIT header](https://github.com/mojohaus/animal-sniffer/blob/animal-sniffer-parent-1.18/animal-sniffer-annotations/pom.xml). JUnit 4.13.2: [EPL-1.0](https://github.com/junit-team/junit4/blob/r4.13.2/LICENSE-junit.txt). Desugared JDK libraries preserve GPL-2.0 with the Classpath Exception and separately licensed MIT material; see their upstream license and POM terms. `dbus` is an unmodified locked dependency reference, licensed MPL-2.0, used by the Linux notification transitive (Linux is outside this release). Its license is preserved and no dbus source/binary is distributed here.
