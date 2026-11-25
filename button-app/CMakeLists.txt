# The following five lines of boilerplate have to be in your project's
# CMakeLists in this exact order for cmake to work correctly
cmake_minimum_required(VERSION 3.22)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(button-app)

if("$ENV{SKIP_GITLEAKS}" STREQUAL "1")
    message(WARNING "Gitleaks check skipped")
else()
    find_program(GITLEAKS_EXE NAMES gitleaks REQUIRED)

    get_filename_component(GITLEAKS_CFG "${CMAKE_CURRENT_SOURCE_DIR}/../.gitleaks.toml" ABSOLUTE)
    set(GITLEAKS_ARGS dir . --config ${GITLEAKS_CFG} --no-banner --exit-code 1)

    add_custom_target(gitleaks_check ALL
        COMMAND "${GITLEAKS_EXE}" ${GITLEAKS_ARGS}
        COMMENT "Running Gitleaks secret check..."
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
        VERBATIM
    )
    add_dependencies(app gitleaks_check)
endif()