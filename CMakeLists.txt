cmake_minimum_required(VERSION 3.28)
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0 CACHE STRING "Liquid Glass needs macOS 26")
project(Sotto VERSION 0.1 LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_OBJCXX_STANDARD 23)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
add_compile_options(-Wall -Wextra)

# Portable C++23 model of a dictation session. No Apple headers.
add_library(SottoCore STATIC Sources/Core/Session.cpp Sources/Core/ScriptedRecognizer.cpp
  Sources/Core/ShortcutGesture.cpp)
target_include_directories(SottoCore PUBLIC Sources/Core)

file(GLOB SOTTO_SOUNDS CONFIGURE_DEPENDS Resources/Sounds/*.wav Resources/Sounds/LICENSE-Hex.txt)

add_executable(Sotto MACOSX_BUNDLE
  Sources/App/main.mm
  Sources/App/AppDelegate.mm
  Sources/App/AudioInput.mm
  Sources/App/DictationController.mm
  Sources/App/DictationHUD.mm
  Sources/App/HotKey.mm
  Sources/App/Keychain.mm
  Sources/App/OpenAIRealtimeRecognizer.mm
  Sources/App/Recognizers.mm
  Sources/App/Shortcut.mm
  Sources/App/ShortcutViews.mm
  Sources/App/StatusItemController.mm
  Sources/App/TextInserter.mm
  Sources/App/SettingsWindowController.mm
  Sources/App/WelcomeWindowController.mm
  ${SOTTO_SOUNDS})
# The license travels with the sounds, as its terms require.
set_source_files_properties(${SOTTO_SOUNDS} PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Sounds)
target_compile_options(Sotto PRIVATE -fobjc-arc)
target_link_libraries(Sotto PRIVATE SottoCore
  "-framework AppKit" "-framework Carbon" "-framework QuartzCore" "-framework Symbols"
  "-framework AVFoundation" "-framework CoreMedia" "-framework Security")
set_target_properties(Sotto PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/Resources/Info.plist.in)

# Ad-hoc signatures change with every build, and macOS then asks again for
# keychain and microphone access. A real identity keeps both, for example
#   cmake -B build -DSOTTO_CODESIGN_IDENTITY="Apple Development"
set(SOTTO_CODESIGN_IDENTITY "-" CACHE STRING "Identity for codesign; - signs ad hoc")
add_custom_command(TARGET Sotto POST_BUILD
  COMMAND codesign --force --sign "${SOTTO_CODESIGN_IDENTITY}" --identifier com.example.Sotto
          "$<TARGET_BUNDLE_DIR:Sotto>"
  VERBATIM)

enable_testing()
add_executable(SessionTests Tests/SessionTests.cpp)
target_link_libraries(SessionTests PRIVATE SottoCore)
add_test(NAME SessionTests COMMAND SessionTests)
add_executable(ShortcutGestureTests Tests/ShortcutGestureTests.cpp)
target_link_libraries(ShortcutGestureTests PRIVATE SottoCore)
add_test(NAME ShortcutGestureTests COMMAND ShortcutGestureTests)
