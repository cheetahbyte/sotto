cmake_minimum_required(VERSION 3.28)
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0 CACHE STRING "Liquid Glass needs macOS 26")
project(Sotto VERSION 0.1 LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_OBJCXX_STANDARD 23)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_compile_options(
  -Wall -Wextra -Wpedantic -Werror
  -Wconversion -Wsign-conversion -Wshadow -Wformat=2 -Wnull-dereference
  -Wdouble-promotion -Wimplicit-fallthrough -Wunsafe-buffer-usage
  -Wlifetime-safety -Wthread-safety -Wdangling)
add_compile_definitions(_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE)

set(SOTTO_SANITIZE "" CACHE STRING "Sanitizers for all targets, for example address,undefined or thread")
if(SOTTO_SANITIZE)
  add_compile_options(-fsanitize=${SOTTO_SANITIZE} -fno-omit-frame-pointer -fno-sanitize-recover=all)
  add_link_options(-fsanitize=${SOTTO_SANITIZE})
endif()

add_library(SottoCore STATIC Sources/Core/Session.cpp Sources/Core/ShortcutGesture.cpp)
target_include_directories(SottoCore PUBLIC Sources/Core)

file(GLOB SOTTO_SOUNDS CONFIGURE_DEPENDS Resources/Sounds/*.wav Resources/Sounds/LICENSE-Hex.txt)

add_executable(Sotto MACOSX_BUNDLE
  Sources/App/main.mm
  Sources/App/AppDelegate.mm
  Sources/App/AudioInput.mm
  Sources/App/DictationController.mm
  Sources/App/DictationHUD.mm
  Sources/App/FeedbackSound.mm
  Sources/App/HotKey.mm
  Sources/App/Keychain.mm
  Sources/App/MicrophoneCapture.mm
  Sources/App/OpenAIRealtimeRecognizer.mm
  Sources/App/Recognizers.mm
  Sources/App/Shortcut.mm
  Sources/App/ShortcutRecorderView.mm
  Sources/App/StatusItemController.mm
  Sources/App/TextInserter.mm
  Sources/App/SettingsPanes.mm
  Sources/App/SettingsWindowController.mm
  Sources/App/WelcomeWindowController.mm
  ${SOTTO_SOUNDS})
set_source_files_properties(${SOTTO_SOUNDS} PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Sounds)
target_compile_options(Sotto PRIVATE -fobjc-arc)
target_link_libraries(Sotto PRIVATE SottoCore
  "-framework AppKit" "-framework Carbon" "-framework QuartzCore" "-framework Symbols"
  "-framework AVFoundation" "-framework CoreMedia" "-framework Security")
set_target_properties(Sotto PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/Resources/Info.plist.in)

set(SOTTO_CODESIGN_IDENTITY "-" CACHE STRING "Identity for codesign; - signs ad hoc")
add_custom_command(TARGET Sotto POST_BUILD
  COMMAND codesign --force --sign "${SOTTO_CODESIGN_IDENTITY}" --identifier com.example.Sotto
          "$<TARGET_BUNDLE_DIR:Sotto>"
  VERBATIM)

find_program(CLANG_TIDY NAMES clang-tidy HINTS /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin)
if(CLANG_TIDY)
  file(GLOB SOTTO_TIDY_SOURCES CONFIGURE_DEPENDS Sources/App/*.mm Sources/Core/*.cpp Tests/*.cpp)
  add_custom_target(tidy
    COMMAND ${CLANG_TIDY} -p ${CMAKE_BINARY_DIR} --quiet ${SOTTO_TIDY_SOURCES}
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    VERBATIM)
endif()

enable_testing()
add_executable(SessionTests Tests/SessionTests.cpp)
target_link_libraries(SessionTests PRIVATE SottoCore)
add_test(NAME SessionTests COMMAND SessionTests)
add_executable(ShortcutGestureTests Tests/ShortcutGestureTests.cpp)
target_link_libraries(ShortcutGestureTests PRIVATE SottoCore)
add_test(NAME ShortcutGestureTests COMMAND ShortcutGestureTests)
