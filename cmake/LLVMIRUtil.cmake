cmake_minimum_required(VERSION 3.27)

include(CMakeParseArguments)
include(LLVMIRUtilInternal)
include(Util)

llvmir_setup()


# public (client) interface macros/functions

function(llvmir_attach_bc_target)
  set(options ATTACH_TO_DEPENDENT_STATIC_LIBS)
  set(oneValueArgs TARGET DEPENDS OUTPUT_DIR)
  set(multiValueArgs)
  cmake_parse_arguments(LLVMIR_ATTACH
    "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(LLVMIR_ATTACH_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "llvmir_attach_bc_target: extraneous arguments provided")
  endif()

  if(NOT LLVMIR_ATTACH_TARGET)
    message(FATAL_ERROR "llvmir_attach_bc_target: missing TARGET option")
  endif()
  set(TRGT ${LLVMIR_ATTACH_TARGET})

  if(NOT LLVMIR_ATTACH_DEPENDS)
    message(FATAL_ERROR "llvmir_attach_bc_target: missing DEPENDS option")
  endif()
  set(DEPENDS_TRGT ${LLVMIR_ATTACH_DEPENDS})

  if(LLVMIR_ATTACH_OUTPUT_DIR)
    if(EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR} AND NOT IS_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
      message(FATAL_ERROR "llvmir_attach_bc_target: OUTPUT must be a directory")
    elseif(NOT EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR})
      file(MAKE_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
    endif()
    set(WORK_DIR ${LLVMIR_ATTACH_OUTPUT_DIR})
  endif()


  ## preamble
  set(OUT_LLVMIR_FILES "")
  set(FULL_OUT_LLVMIR_FILES "")

  llvmir_check_non_llvmir_target_properties(${DEPENDS_TRGT})

  # the 3.x and above INTERFACE_SOURCES does not participate in the compilation of a target

  # if the property does not exist the related variable is not defined
  get_property(IN_FILES TARGET ${DEPENDS_TRGT} PROPERTY SOURCES)
  get_property(LINKER_LANGUAGE TARGET ${DEPENDS_TRGT} PROPERTY LINKER_LANGUAGE)
  get_property(EXTERNAL_TYPE TARGET ${DEPENDS_TRGT} PROPERTY TYPE)
  get_property(LINK_DEPENDS TARGET ${DEPENDS_TRGT} PROPERTY LINK_DEPENDS)
  get_property(LINK_FLAGS TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS)
  get_property(LINK_FLAGS_${CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE})
  get_property(INTERFACE_LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY INTERFACE_LINK_LIBRARIES)
  get_property(LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE})
  get_property(SHORT_NAME TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_SHORT_NAME)

  debug("@llvmir_attach_bc_target ${DEPENDS_TRGT} linker lang: ${LINKER_LANGUAGE}")

  llvmir_set_compiler(${LINKER_LANGUAGE})

  ## command options
  if(NOT WORK_DIR)
    set(WORK_DIR "${CMAKE_CURRENT_BINARY_DIR}/${LLVMIR_DIR}/${TRGT}")
    file(MAKE_DIRECTORY ${WORK_DIR})
  endif()

  # compile definitions
  llvmir_extract_compile_defs_properties(IN_DEFS ${DEPENDS_TRGT})

  # includes
  llvmir_extract_include_dirs_properties(IN_INCLUDES ${DEPENDS_TRGT})

  # language standards flags
  llvmir_extract_standard_flags(IN_STANDARD_FLAGS ${DEPENDS_TRGT} ${LINKER_LANGUAGE})

  # compile options
  llvmir_extract_compile_option_properties(IN_COMPILE_OPTIONS ${DEPENDS_TRGT})

  # compile flags
  llvmir_extract_compile_flags(IN_COMPILE_FLAGS ${DEPENDS_TRGT})

  # compile lang flags
  llvmir_extract_lang_flags(IN_LANG_FLAGS ${LINKER_LANGUAGE})

  set(tmp_IN_FILES "")
  foreach(FILE ${IN_FILES})
    set(tmp ${FILE})
    if(NOT IS_ABSOLUTE ${FILE})
      get_target_property(SOURCE_DIR ${DEPENDS_TRGT} SOURCE_DIR)
      get_filename_component(ABS_IN_FILE ${FILE} ABSOLUTE BASE_DIR ${SOURCE_DIR})
      set(tmp ${ABS_IN_FILE})
    endif()

    list(APPEND tmp_IN_FILES ${tmp})
  endforeach()
  set(IN_FILES ${tmp_IN_FILES})


  # if(LLVMIR_ATTACH_ATTACH_TO_DEPENDENT_STATIC_LIBS)
    # message(STATUS "ATTACH_TO_DEPENDENT_STATIC_LIBS option is turned on. Attaching to dependent static libraries of target ${TRGT}.")
  
    # message("LINK_LIBRARIES ${LINK_LIBRARIES}")

    set(STATIC_LIBRARIES "")

    # Find all statically linked libraries
    foreach(LINK_LIB ${LINK_LIBRARIES})
      if(TARGET ${LINK_LIB})
        get_target_property(type ${LINK_LIB} TYPE)

        if(${type} STREQUAL "INTERFACE_LIBRARY")
          get_target_property(TMP_INTERFACE_LINK_LIBRARIES ${LINK_LIB} INTERFACE_LINK_LIBRARIES) #kokkoscore;kokkoscontainers;kokkosalgorithms;kokkossimd

          while(TMP_INTERFACE_LINK_LIBRARIES)
            list(GET TMP_INTERFACE_LINK_LIBRARIES 0 CURRENT_LIB)
            list(REMOVE_AT TMP_INTERFACE_LINK_LIBRARIES 0)

            if(TARGET ${CURRENT_LIB})
              get_target_property(type ${CURRENT_LIB} TYPE)
              if(${type} STREQUAL "STATIC_LIBRARY")
                list(APPEND STATIC_LIBRARIES ${CURRENT_LIB})
              elseif(${type} STREQUAL "INTERFACE_LIBRARY")
                get_target_property(CURRENT_LIB_LINK_LIBRARY ${CURRENT_LIB} INTERFACE_LINK_LIBRARIES)
                if(${CURRENT_LIB_LINK_LIBRARY})
                  list(APPEND TMP_INTERFACE_LINK_LIBRARIES ${CURRENT_LIB_LINK_LIBRARY})
                endif()
              endif()
            endif()
          endwhile()

        elseif(${type} STREQUAL "STATIC_LIBRARY")
          list(APPEND STATIC_LIBRARIES ${LINK_LIB})
        endif()
      endif()
    endforeach()
  # endif()


  set(header_exts ".h;.hh;.hpp;.h++;.hxx")
  set(STATIC_LIBRARIES_IN_DIRS "")
  set(STATIC_LIBRARIES_IN_FILES "")

  foreach(STATIC_LIBRARY ${STATIC_LIBRARIES})
    get_target_property(STATIC_LIBRARY_IN_DIRS ${STATIC_LIBRARY} INCLUDE_DIRECTORIES)
    if(STATIC_LIBRARY_IN_DIRS)
      foreach(STATIC_LIBRARY_IN_DIR STATIC_LIBRARY_IN_DIRS)
        list(APPEND STATIC_LIBRARIES_IN_DIRS "-I${STATIC_LIBRARY_IN_DIR}")
      endforeach()
    endif()


    get_target_property(STATIC_LIBRARY_SOURCES ${STATIC_LIBRARY} SOURCES)
    get_target_property(STATIC_LIBRARY_SOURCE_DIR ${STATIC_LIBRARY} SOURCE_DIR)
    message(STATUS "Attaching to dependent static library ${STATIC_LIBRARY} of target ${TRGT}.")

    foreach(SOURCE ${STATIC_LIBRARY_SOURCES})
      if(NOT EXISTS ${SOURCE})
        continue()
      endif()

      get_filename_component(FILE_EXT ${SOURCE} LAST_EXT)
      string(TOLOWER ${FILE_EXT} FILE_EXT)
      list(FIND header_exts ${FILE_EXT} _index)

      if(${_index} GREATER -1) # is a header file
        set(tmp_HEADER ${SOURCE})
        if(NOT IS_ABSOLUTE ${SOURCE})
          set(tmp_SOURCE "${STATIC_LIBRARY_SOURCE_DIR}/${SOURCE}")
        endif()
        get_filename_component(HEADER_DIR ${tmp_HEADER} DIRECTORY)

        list(APPEND STATIC_LIBRARIES_IN_DIRS "-I${HEADER_DIR}")
      else() # is a source file
        set(tmp_SOURCE ${SOURCE})
        if(NOT IS_ABSOLUTE ${SOURCE})
          set(tmp_SOURCE "${STATIC_LIBRARY_SOURCE_DIR}/${SOURCE}")
        endif()
        list(APPEND STATIC_LIBRARIES_IN_FILES ${tmp_SOURCE})
      endif()
    endforeach()
  endforeach()

  list(REMOVE_DUPLICATES STATIC_LIBRARIES_IN_DIRS)
  list(APPEND IN_INCLUDES ${STATIC_LIBRARIES_IN_DIRS})

  list(REMOVE_DUPLICATES STATIC_LIBRARIES_IN_FILES)

  if(LLVMIR_ATTACH_ATTACH_TO_DEPENDENT_STATIC_LIBS)
    list(APPEND IN_FILES ${STATIC_LIBRARIES_IN_FILES})
  endif()

  if(${OpenMP_FOUND})
    set(OPENMP_FLAGS "${OpenMP_CXX_FLAGS}")
  endif()


  # main operations
  foreach(IN_FILE ${IN_FILES})
    get_filename_component(OUT_FILE ${IN_FILE} NAME)
    set(OUT_LLVMIR_FILE "${OUT_FILE}.${LLVMIR_BINARY_FMT_SUFFIX}")
    set(FULL_OUT_LLVMIR_FILE "${WORK_DIR}/${OUT_LLVMIR_FILE}")

    # compile definitions per source file
    llvmir_extract_compile_defs_properties(IN_FILE_DEFS ${IN_FILE})

    # compile flags per source file
    llvmir_extract_lang_flags(IN_FILE_COMPILE_FLAGS ${IN_FILE})

    # stitch all args together
    catuniq(CURRENT_DEFS ${IN_DEFS} ${IN_FILE_DEFS})
    debug("@llvmir_attach_bc_target ${DEPENDS_TRGT} defs: ${CURRENT_DEFS}")

    catuniq(CURRENT_COMPILE_FLAGS ${IN_COMPILE_FLAGS} ${IN_FILE_COMPILE_FLAGS})
    debug("@llvmir_attach_bc_target ${DEPENDS_TRGT} compile flags: ${CURRENT_COMPILE_FLAGS}")


    message("in include ${IN_INCLUDES}")


    set(CMD_ARGS "-emit-llvm" "-c" ${OPENMP_FLAGS} ${BUILD_FLAGS} ${IN_STANDARD_FLAGS} ${IN_LANG_FLAGS}
      ${IN_COMPILE_OPTIONS} ${CURRENT_COMPILE_FLAGS} ${CURRENT_DEFS})

    add_custom_command(OUTPUT ${FULL_OUT_LLVMIR_FILE}
      COMMAND ${LLVMIR_COMPILER}
      ARGS ${CMD_ARGS} "-I$<JOIN:$<TARGET_PROPERTY:${DEPENDS_TRGT},INCLUDE_DIRECTORIES>,;-I>" ${IN_FILE} -o ${FULL_OUT_LLVMIR_FILE}
      DEPENDS ${IN_FILE}
      IMPLICIT_DEPENDS ${LINKER_LANGUAGE} ${IN_FILE}
      COMMENT "Generating LLVM bitcode ${OUT_LLVMIR_FILE}"
      COMMAND_EXPAND_LISTS
      VERBATIM)

    list(APPEND OUT_LLVMIR_FILES ${OUT_LLVMIR_FILE})
    list(APPEND FULL_OUT_LLVMIR_FILES ${FULL_OUT_LLVMIR_FILE})
  endforeach()

  ## postamble

  # setup custom target
  add_custom_target(${TRGT} DEPENDS ${FULL_OUT_LLVMIR_FILES})
  add_dependencies(${TRGT} ${DEPENDS_TRGT})

  set_property(TARGET ${TRGT} PROPERTY LLVMIR_TYPE ${LLVMIR_BINARY_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE ${EXTERNAL_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_DIR ${WORK_DIR})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_FILES ${OUT_LLVMIR_FILES})
  set_property(TARGET ${TRGT} PROPERTY LINKER_LANGUAGE ${LINKER_LANGUAGE})
  set_property(TARGET ${TRGT} PROPERTY LINK_DEPENDS ${LINK_DEPENDS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS ${LINK_FLAGS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} ${LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY INTERFACE_LINK_LIBRARIES ${INTERFACE_LINK_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES ${LINK_INTERFACE_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} ${LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY EXCLUDE_FROM_ALL On)
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_SHORT_NAME ${SHORT_NAME})
endfunction()

#

function(llvmir_attach_opt_pass_target)
  set(options)
  set(oneValueArgs TARGET DEPENDS PASSE_PLUGING OUTPUT_DIR)
  set(multiValueArgs PASSES)
  cmake_parse_arguments(LLVMIR_ATTACH
    "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(LLVMIR_ATTACH_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "llvmir_attach_opt_pass_target: extraneous arguments provided")
  endif()

  if(NOT LLVMIR_ATTACH_TARGET)
    message(FATAL_ERROR "llvmir_attach_opt_pass_target: missing TARGET option")
  endif()
  set(TRGT ${LLVMIR_ATTACH_TARGET})

  if(NOT LLVMIR_ATTACH_DEPENDS)
    message(FATAL_ERROR "llvmir_attach_opt_pass_target: missing DEPENDS option")
  endif()
  set(DEPENDS_TRGT ${LLVMIR_ATTACH_DEPENDS})

  if(NOT LLVMIR_ATTACH_PASSES)
    message(FATAL_ERROR "llvmir_attach_opt_pass_target: missing PASSES option")
  endif()
  set(PASSES ${LLVMIR_ATTACH_PASSES})
  string(REPLACE ";" "," PASSES "${PASSES}")
  set(PASSES -passes=${PASSES})

  if(LLVMIR_ATTACH_PASSE_PLUGING)
    if(NOT EXISTS ${LLVMIR_ATTACH_PASSE_PLUGING})
      message(FATAL_ERROR "llvmir_attach_opt_pass_target: PASSES_PLUGINGS ${PASSE_PLUGING} doesn't exist")
    endif()
    set(PASSE_PLUGING -load-pass-plugin=${LLVMIR_ATTACH_PASSE_PLUGING})
  endif()

  if(LLVMIR_ATTACH_OUTPUT_DIR)
    if(EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR} AND NOT IS_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
      message(FATAL_ERROR "llvmir_attach_opt_pass_target: OUTPUT must be a directory")
    elseif(NOT EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR})
      file(MAKE_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
    endif()
    set(WORK_DIR ${LLVMIR_ATTACH_OUTPUT_DIR})
  endif()


  ## preamble
  llvmir_check_target_properties(${DEPENDS_TRGT})

  set(OUT_LLVMIR_FILES "")
  set(FULL_OUT_LLVMIR_FILES "")

  get_property(IN_LLVMIR_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_TYPE)
  get_property(LLVMIR_EXTERNAL_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE)
  get_property(IN_LLVMIR_DIR TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_DIR)
  get_property(IN_LLVMIR_FILES TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_FILES)
  get_property(LINKER_LANGUAGE TARGET ${DEPENDS_TRGT} PROPERTY LINKER_LANGUAGE)
  get_property(LINK_DEPENDS TARGET ${DEPENDS_TRGT} PROPERTY LINK_DEPENDS)
  get_property(LINK_FLAGS TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS)
  get_property(LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE})
  get_property(INTERFACE_LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY INTERFACE_LINK_LIBRARIES)
  get_property(LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE})
  get_property(SHORT_NAME TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_SHORT_NAME)

  if(NOT "${IN_LLVMIR_TYPE}" STREQUAL "${LLVMIR_BINARY_TYPE}")
    message(FATAL_ERROR "Cannot attach ${TRGT} to target of type: ${IN_LLVMIR_TYPE}.")
  endif()

  if("${LINKER_LANGUAGE}" STREQUAL "")
    message(FATAL_ERROR "Linker language for target ${DEPENDS_TRGT} must be set.")
  endif()


  ## main operations
  if(NOT WORK_DIR)
    set(WORK_DIR "${CMAKE_CURRENT_BINARY_DIR}/${LLVMIR_DIR}/${TRGT}")
    file(MAKE_DIRECTORY ${WORK_DIR})
  endif()

  foreach(IN_LLVMIR_FILE ${IN_LLVMIR_FILES})
    get_filename_component(OUT_FILE ${IN_LLVMIR_FILE} NAME_WE)
    set(INFILE "${IN_LLVMIR_DIR}/${IN_LLVMIR_FILE}")
    set(OUT_LLVMIR_FILE "${OUT_FILE}.${LLVMIR_BINARY_FMT_SUFFIX}")
    set(FULL_OUT_LLVMIR_FILE "${WORK_DIR}/${OUT_LLVMIR_FILE}")

    add_custom_command(
      OUTPUT ${FULL_OUT_LLVMIR_FILE}
      COMMAND ${LLVMIR_OPT} 
      ARGS ${PASSES} ${PASSE_PLUGING} ${INFILE} -o ${FULL_OUT_LLVMIR_FILE}
      DEPENDS ${INFILE}
      COMMENT "Applying ${PASSES} passes on ${IN_LLVMIR_FILE} and generating LLVM bitcode into ${OUT_LLVMIR_FILE}"
      VERBATIM
    )

    list(APPEND OUT_LLVMIR_FILES ${OUT_LLVMIR_FILE})
    list(APPEND FULL_OUT_LLVMIR_FILES ${FULL_OUT_LLVMIR_FILE})
  endforeach()


  ## postamble

  # setup custom target
  add_custom_target(${TRGT} DEPENDS ${FULL_OUT_LLVMIR_FILES})
  add_dependencies(${TRGT} ${DEPENDS_TRGT})

  set_property(TARGET ${TRGT} PROPERTY LLVMIR_TYPE ${LLVMIR_BINARY_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE ${LLVMIR_EXTERNAL_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_DIR ${WORK_DIR})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_FILES ${OUT_LLVMIR_FILES})
  set_property(TARGET ${TRGT} PROPERTY LINKER_LANGUAGE ${LINKER_LANGUAGE})
  set_property(TARGET ${TRGT} PROPERTY LINK_DEPENDS ${LINK_DEPENDS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS ${LINK_FLAGS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} ${LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY INTERFACE_LINK_LIBRARIES ${INTERFACE_LINK_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES ${LINK_INTERFACE_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} ${LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY EXCLUDE_FROM_ALL On)
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_SHORT_NAME ${SHORT_NAME})
endfunction()

#

function(llvmir_attach_disassemble_target)
  set(options)
  set(oneValueArgs TARGET DEPENDS OUTPUT_DIR)
  set(multiValueArgs)
  cmake_parse_arguments(LLVMIR_ATTACH
    "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(LLVMIR_ATTACH_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "llvmir_attach_disassemble_target: extraneous arguments provided")
  endif()

  if(NOT LLVMIR_ATTACH_TARGET)
    message(FATAL_ERROR "llvmir_attach_disassemble_target: missing TARGET option")
  endif()
  set(TRGT ${LLVMIR_ATTACH_TARGET})

  if(NOT LLVMIR_ATTACH_DEPENDS)
    message(FATAL_ERROR "llvmir_attach_disassemble_target: missing DEPENDS option")
  endif()
  set(DEPENDS_TRGT ${LLVMIR_ATTACH_DEPENDS})

  if(LLVMIR_ATTACH_OUTPUT_DIR)
    if(EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR} AND NOT IS_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
      message(FATAL_ERROR "llvmir_attach_disassemble_target: OUTPUT must be a directory")
    elseif(NOT EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR})
      file(MAKE_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
    endif()
    set(WORK_DIR ${LLVMIR_ATTACH_OUTPUT_DIR})
  endif()

  ## preamble
  llvmir_check_target_properties(${DEPENDS_TRGT})

  set(OUT_LLVMIR_FILES "")
  set(FULL_OUT_LLVMIR_FILES "")

  get_property(IN_LLVMIR_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_TYPE)
  get_property(LLVMIR_EXTERNAL_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE)
  get_property(IN_LLVMIR_DIR TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_DIR)
  get_property(IN_LLVMIR_FILES TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_FILES)
  get_property(LINKER_LANGUAGE TARGET ${DEPENDS_TRGT} PROPERTY LINKER_LANGUAGE)
  get_property(LINK_DEPENDS TARGET ${DEPENDS_TRGT} PROPERTY LINK_DEPENDS)
  get_property(LINK_FLAGS TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS)
  get_property(LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE})
  get_property(INTERFACE_LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY INTERFACE_LINK_LIBRARIES)
  get_property(LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE})
  get_property(SHORT_NAME TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_SHORT_NAME)

  if(NOT "${IN_LLVMIR_TYPE}" STREQUAL "${LLVMIR_BINARY_TYPE}")
    message(FATAL_ERROR "Cannot attach ${TRGT} to a ${IN_LLVMIR_TYPE} target.")
  endif()


  ## main operations
  if(NOT WORK_DIR)
    set(WORK_DIR "${CMAKE_CURRENT_BINARY_DIR}/${LLVMIR_DIR}/${TRGT}")
    file(MAKE_DIRECTORY ${WORK_DIR})
  endif()

  foreach(IN_LLVMIR_FILE ${IN_LLVMIR_FILES})
    get_filename_component(OUT_FILE ${IN_LLVMIR_FILE} NAME_WE)
    set(INFILE "${IN_LLVMIR_DIR}/${IN_LLVMIR_FILE}")
    set(OUT_LLVMIR_FILE "${OUT_FILE}.${LLVMIR_TEXT_FMT_SUFFIX}")
    set(FULL_OUT_LLVMIR_FILE "${WORK_DIR}/${OUT_LLVMIR_FILE}")

    add_custom_command(
      OUTPUT ${FULL_OUT_LLVMIR_FILE}
      COMMAND ${LLVMIR_DISASSEMBLER}
      ARGS ${INFILE} -o ${FULL_OUT_LLVMIR_FILE}
      DEPENDS ${INFILE}
      COMMENT "Disassembling LLVM bitcode ${IN_LLVMIR_FILE} into ${OUT_LLVMIR_FILE}"
      VERBATIM
    )

    list(APPEND OUT_LLVMIR_FILES ${OUT_LLVMIR_FILE})
    list(APPEND FULL_OUT_LLVMIR_FILES ${FULL_OUT_LLVMIR_FILE})
  endforeach()


  ## postamble

  # setup custom target
  add_custom_target(${TRGT} DEPENDS ${FULL_OUT_LLVMIR_FILES})
  add_dependencies(${TRGT} ${DEPENDS_TRGT})

  set_property(TARGET ${TRGT} PROPERTY LLVMIR_TYPE ${LLVMIR_TEXT_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE ${LLVMIR_EXTERNAL_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_DIR ${WORK_DIR})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_FILES ${OUT_LLVMIR_FILES})
  set_property(TARGET ${TRGT} PROPERTY LINKER_LANGUAGE ${LINKER_LANGUAGE})
  set_property(TARGET ${TRGT} PROPERTY LINK_DEPENDS ${LINK_DEPENDS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS ${LINK_FLAGS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} ${LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY INTERFACE_LINK_LIBRARIES ${INTERFACE_LINK_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES ${LINK_INTERFACE_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} ${LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY EXCLUDE_FROM_ALL On)
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_SHORT_NAME ${SHORT_NAME})
endfunction()

#

function(llvmir_attach_assemble_target)
  set(options)
  set(oneValueArgs TARGET DEPENDS OUTPUT_DIR)
  set(multiValueArgs)
  cmake_parse_arguments(LLVMIR_ATTACH
    "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT LLVMIR_ATTACH_TARGET)
    message(FATAL_ERROR "llvmir_attach_assemble_target: missing TARGET option")
  endif()
  set(TRGT ${LLVMIR_ATTACH_TARGET})

  if(NOT LLVMIR_ATTACH_DEPENDS)
    message(FATAL_ERROR "llvmir_attach_assemble_target: missing DEPENDS option")
  endif()
  set(DEPENDS_TRGT ${LLVMIR_ATTACH_DEPENDS})

  if(LLVMIR_ATTACH_OUTPUT_DIR)
    if(EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR} AND NOT IS_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
      message(FATAL_ERROR "llvmir_attach_assemble_target: OUTPUT must be a directory")
    elseif(NOT EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR})
      file(MAKE_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
    endif()
    set(WORK_DIR ${LLVMIR_ATTACH_OUTPUT_DIR})
  endif()

  ## preamble
  llvmir_check_target_properties(${DEPENDS_TRGT})

  set(OUT_LLVMIR_FILES "")
  set(FULL_OUT_LLVMIR_FILES "")

  get_property(IN_LLVMIR_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_TYPE)
  get_property(LLVMIR_EXTERNAL_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE)
  get_property(IN_LLVMIR_DIR TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_DIR)
  get_property(IN_LLVMIR_FILES TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_FILES)
  get_property(LINKER_LANGUAGE TARGET ${DEPENDS_TRGT} PROPERTY LINKER_LANGUAGE)
  get_property(LINK_DEPENDS TARGET ${DEPENDS_TRGT} PROPERTY LINK_DEPENDS)
  get_property(LINK_FLAGS TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS)
  get_property(LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE})
  get_property(INTERFACE_LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY INTERFACE_LINK_LIBRARIES)
  get_property(LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE})
  get_property(SHORT_NAME TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_SHORT_NAME)

  if(NOT "${IN_LLVMIR_TYPE}" STREQUAL "${LLVMIR_TEXT_TYPE}")
    message(FATAL_ERROR "Cannot attach ${TRGT} to a ${IN_LLVMIR_TYPE} target.")
  endif()


  ## main operations
  if(NOT WORK_DIR)
    set(WORK_DIR "${CMAKE_CURRENT_BINARY_DIR}/${LLVMIR_DIR}/${TRGT}")
    file(MAKE_DIRECTORY ${WORK_DIR})
  endif()

  foreach(IN_LLVMIR_FILE ${IN_LLVMIR_FILES})
    get_filename_component(OUT_FILE ${IN_LLVMIR_FILE} NAME_WE)
    set(INFILE "${IN_LLVMIR_DIR}/${IN_LLVMIR_FILE}")
    set(OUT_LLVMIR_FILE "${OUT_FILE}.${LLVMIR_BINARY_FMT_SUFFIX}")
    set(FULL_OUT_LLVMIR_FILE "${WORK_DIR}/${OUT_LLVMIR_FILE}")

    add_custom_command(
      OUTPUT ${FULL_OUT_LLVMIR_FILE}
      COMMAND ${LLVMIR_ASSEMBLER}
      ARGS ${INFILE} -o ${FULL_OUT_LLVMIR_FILE}
      DEPENDS ${INFILE}
      COMMENT "Assembling LLVM bitcode ${IN_LLVMIR_FILE} into ${OUT_LLVMIR_FILE}"
      VERBATIM
    )

    list(APPEND OUT_LLVMIR_FILES ${OUT_LLVMIR_FILE})
    list(APPEND FULL_OUT_LLVMIR_FILES ${FULL_OUT_LLVMIR_FILE})
  endforeach()


  ## postamble

  # setup custom target
  add_custom_target(${TRGT} DEPENDS ${FULL_OUT_LLVMIR_FILES})
  add_dependencies(${TRGT} ${DEPENDS_TRGT})

  set_property(TARGET ${TRGT} PROPERTY LLVMIR_TYPE ${LLVMIR_BINARY_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE ${LLVMIR_EXTERNAL_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_DIR ${WORK_DIR})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_FILES ${OUT_LLVMIR_FILES})
  set_property(TARGET ${TRGT} PROPERTY LINKER_LANGUAGE ${LINKER_LANGUAGE})
  set_property(TARGET ${TRGT} PROPERTY LINK_DEPENDS ${LINK_DEPENDS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS ${LINK_FLAGS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} ${LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY INTERFACE_LINK_LIBRARIES ${INTERFACE_LINK_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES ${LINK_INTERFACE_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} ${LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY EXCLUDE_FROM_ALL On)
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_SHORT_NAME ${SHORT_NAME})
endfunction()

#

function(llvmir_attach_link_target)
  set(options)
  set(oneValueArgs TARGET DEPENDS OUTPUT_DIR)
  set(multiValueArgs)
  cmake_parse_arguments(LLVMIR_ATTACH
    "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT LLVMIR_ATTACH_TARGET)
    message(FATAL_ERROR "llvmir_attach_link_target: missing TARGET option")
  endif()
  set(TRGT ${LLVMIR_ATTACH_TARGET})

  if(NOT LLVMIR_ATTACH_DEPENDS)
    message(FATAL_ERROR "llvmir_attach_link_target: missing DEPENDS option")
  endif()
  set(DEPENDS_TRGT ${LLVMIR_ATTACH_DEPENDS})

  if(LLVMIR_ATTACH_OUTPUT_DIR)
    if(EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR} AND NOT IS_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
      message(FATAL_ERROR "llvmir_attach_link_target: OUTPUT must be a directory")
    elseif(NOT EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR})
      file(MAKE_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
    endif()
    set(WORK_DIR ${LLVMIR_ATTACH_OUTPUT_DIR})
  endif()

  ## preamble
  llvmir_check_target_properties(${DEPENDS_TRGT})

  set(OUT_LLVMIR_FILES "")
  set(FULL_OUT_LLVMIR_FILES "")

  get_property(IN_LLVMIR_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_TYPE)
  get_property(LLVMIR_EXTERNAL_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE)
  get_property(INFILES TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_FILES)
  get_property(IN_LLVMIR_DIR TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_DIR)
  get_property(LINKER_LANGUAGE TARGET ${DEPENDS_TRGT} PROPERTY LINKER_LANGUAGE)
  get_property(LINK_DEPENDS TARGET ${DEPENDS_TRGT} PROPERTY LINK_DEPENDS)
  get_property(LINK_FLAGS TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS)
  get_property(LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE})
  get_property(INTERFACE_LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY INTERFACE_LINK_LIBRARIES)
  get_property(LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE})
  get_property(SHORT_NAME TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_SHORT_NAME)

  if(NOT "${IN_LLVMIR_TYPE}" STREQUAL "${LLVMIR_BINARY_TYPE}")
    message(FATAL_ERROR "Cannot attach ${TRGT} to a ${IN_LLVMIR_TYPE} target.")
  endif()


  ## main operations
  if(NOT WORK_DIR)
    set(WORK_DIR "${CMAKE_CURRENT_BINARY_DIR}/${LLVMIR_DIR}/${TRGT}")
    file(MAKE_DIRECTORY ${WORK_DIR})
  endif()

  set(IN_FULL_LLVMIR_FILES "")
  foreach(IN_LLVMIR_FILE ${INFILES})
    list(APPEND IN_FULL_LLVMIR_FILES "${IN_LLVMIR_DIR}/${IN_LLVMIR_FILE}")
  endforeach()

  set(FULL_OUT_LLVMIR_FILE "${WORK_DIR}/${TRGT}.${LLVMIR_BINARY_FMT_SUFFIX}")
  if(SHORT_NAME)
    set(FULL_OUT_LLVMIR_FILE
      "${WORK_DIR}/${SHORT_NAME}.${LLVMIR_BINARY_FMT_SUFFIX}")
  endif()
  get_filename_component(OUT_LLVMIR_FILE ${FULL_OUT_LLVMIR_FILE} NAME)

  list(APPEND OUT_LLVMIR_FILES ${OUT_LLVMIR_FILE})
  list(APPEND FULL_OUT_LLVMIR_FILES ${FULL_OUT_LLVMIR_FILE})

  # setup custom target
  add_custom_target(${TRGT} DEPENDS ${FULL_OUT_LLVMIR_FILES})
  add_dependencies(${TRGT} ${DEPENDS_TRGT})

  set_property(TARGET ${TRGT} PROPERTY LLVMIR_TYPE ${LLVMIR_BINARY_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE ${LLVMIR_EXTERNAL_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_DIR ${WORK_DIR})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_FILES ${OUT_LLVMIR_FILES})
  set_property(TARGET ${TRGT} PROPERTY LINKER_LANGUAGE ${LINKER_LANGUAGE})
  set_property(TARGET ${TRGT} PROPERTY LINK_DEPENDS ${LINK_DEPENDS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS ${LINK_FLAGS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} ${LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY INTERFACE_LINK_LIBRARIES ${INTERFACE_LINK_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES ${LINK_INTERFACE_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} ${LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY EXCLUDE_FROM_ALL On)
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_SHORT_NAME ${SHORT_NAME})

  add_custom_command(
    OUTPUT ${FULL_OUT_LLVMIR_FILE}
    COMMAND llvm-link
    ARGS -o ${FULL_OUT_LLVMIR_FILE} ${IN_FULL_LLVMIR_FILES}
    DEPENDS ${IN_FULL_LLVMIR_FILES}
    COMMENT "Linking LLVM bitcode ${IN_FULL_LLVMIR_FILES} into ${OUT_LLVMIR_FILE}"
    VERBATIM
  )


  ## postamble
endfunction()

#

function(llvmir_attach_obj_target)
  set(options)
  set(oneValueArgs TARGET DEPENDS OUTPUT_DIR)
  set(multiValueArgs)
  cmake_parse_arguments(LLVMIR_ATTACH
    "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(LLVMIR_ATTACH_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "llvmir_attach_executable: extraneous arguments provided (${LLVMIR_ATTACH_UNPARSED_ARGUMENTS})")
  endif()

  if(NOT LLVMIR_ATTACH_TARGET)
    message(FATAL_ERROR "llvmir_attach_obj_target: missing TARGET option")
  endif()
  set(TRGT ${LLVMIR_ATTACH_TARGET})

  if(NOT LLVMIR_ATTACH_DEPENDS)
    message(FATAL_ERROR "llvmir_attach_obj_target: missing DEPENDS option")
  endif()
  set(DEPENDS_TRGT ${LLVMIR_ATTACH_DEPENDS})

  if(LLVMIR_ATTACH_OUTPUT_DIR)
    if(EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR} AND NOT IS_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
      message(FATAL_ERROR "llvmir_attach_obj_target: OUTPUT must be a directory")
    elseif(NOT EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR})
      file(MAKE_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
    endif()
    set(WORK_DIR ${LLVMIR_ATTACH_OUTPUT_DIR})
  endif()

  ## preamble
  llvmir_check_target_properties(${DEPENDS_TRGT})

  set(OUT_LLVMIR_FILES "")
  set(FULL_OUT_LLVMIR_FILES "")

  get_property(IN_LLVMIR_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_TYPE)
  get_property(LLVMIR_EXTERNAL_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE)
  get_property(INFILES TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_FILES)
  get_property(IN_LLVMIR_DIR TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_DIR)
  get_property(LINKER_LANGUAGE TARGET ${DEPENDS_TRGT} PROPERTY LINKER_LANGUAGE)
  get_property(LINK_DEPENDS TARGET ${DEPENDS_TRGT} PROPERTY LINK_DEPENDS)
  get_property(LINK_FLAGS TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS)
  get_property(LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE})
  get_property(INTERFACE_LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY INTERFACE_LINK_LIBRARIES)
  get_property(LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE})
  get_property(SHORT_NAME TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_SHORT_NAME)

  if(NOT "${IN_LLVMIR_TYPE}" STREQUAL "${LLVMIR_BINARY_TYPE}")
    message(FATAL_ERROR "Cannot attach ${TRGT} to a ${IN_LLVMIR_TYPE} target.")
  endif()

  ## main operations
  if(NOT WORK_DIR)
    set(WORK_DIR "${CMAKE_CURRENT_BINARY_DIR}/${LLVMIR_DIR}/${TRGT}")
    file(MAKE_DIRECTORY ${WORK_DIR})
  endif()

  set(IN_FULL_LLVMIR_FILES "")
  foreach(IN_LLVMIR_FILE ${INFILES})
    list(APPEND IN_FULL_LLVMIR_FILES "${IN_LLVMIR_DIR}/${IN_LLVMIR_FILE}")
  endforeach()

  set(FULL_OUT_LLVMIR_FILE "${WORK_DIR}/${TRGT}.o")
  if(SHORT_NAME)
    set(FULL_OUT_LLVMIR_FILE "${WORK_DIR}/${SHORT_NAME}.o")
  endif()
  get_filename_component(OUT_LLVMIR_FILE ${FULL_OUT_LLVMIR_FILE} NAME)

  list(APPEND OUT_LLVMIR_FILES ${OUT_LLVMIR_FILE})
  list(APPEND FULL_OUT_LLVMIR_FILES ${FULL_OUT_LLVMIR_FILE})

  # setup custom target
  add_custom_target(${TRGT} DEPENDS ${FULL_OUT_LLVMIR_FILES})
  add_dependencies(${TRGT} ${DEPENDS_TRGT})

  set_property(TARGET ${TRGT} PROPERTY LLVMIR_TYPE ${LLVMIR_OBJECT_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE ${LLVMIR_EXTERNAL_TYPE})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_DIR ${WORK_DIR})
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_FILES ${OUT_LLVMIR_FILES})
  set_property(TARGET ${TRGT} PROPERTY LINKER_LANGUAGE ${LINKER_LANGUAGE})
  set_property(TARGET ${TRGT} PROPERTY LINK_DEPENDS ${LINK_DEPENDS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS ${LINK_FLAGS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} ${LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY INTERFACE_LINK_LIBRARIES ${INTERFACE_LINK_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES ${LINK_INTERFACE_LIBRARIES})
  set_property(TARGET ${TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} ${LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY EXCLUDE_FROM_ALL On)
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_SHORT_NAME ${SHORT_NAME})

  add_custom_command(OUTPUT ${FULL_OUT_LLVMIR_FILE}
    COMMAND llc
    ARGS -filetype=obj -o ${FULL_OUT_LLVMIR_FILE} ${IN_FULL_LLVMIR_FILES}
    DEPENDS ${IN_FULL_LLVMIR_FILES}
    COMMENT "Generating object ${OUT_LLVMIR_FILE}"
    VERBATIM
  )

  ## postamble
endfunction()

#

function(llvmir_attach_executable)
  set(options)
  set(oneValueArgs TARGET DEPENDS OUTPUT_DIR)
  set(multiValueArgs)
  cmake_parse_arguments(LLVMIR_ATTACH
    "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(LLVMIR_ATTACH_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "llvmir_attach_executable: extraneous arguments provided (${LLVMIR_ATTACH_UNPARSED_ARGUMENTS})")
  endif()

  if(NOT LLVMIR_ATTACH_TARGET)
    message(FATAL_ERROR "llvmir_attach_executable: missing TARGET option")
  endif()
  set(TRGT ${LLVMIR_ATTACH_TARGET})

  if(NOT LLVMIR_ATTACH_DEPENDS)
    message(FATAL_ERROR "llvmir_attach_executable: missing DEPENDS option")
  endif()
  set(DEPENDS_TRGT ${LLVMIR_ATTACH_DEPENDS})

  if(LLVMIR_ATTACH_OUTPUT_DIR)
    if(EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR} AND NOT IS_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
      message(FATAL_ERROR "llvmir_attach_executable: OUTPUT must be a directory")
    elseif(NOT EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR})
      file(MAKE_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
    endif()
    set(WORK_DIR ${LLVMIR_ATTACH_OUTPUT_DIR})
  endif()


  ## preamble
  llvmir_check_target_properties(${DEPENDS_TRGT})

  get_property(IN_LLVMIR_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_TYPE)
  get_property(LLVMIR_EXTERNAL_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE)
  get_property(INFILES TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_FILES)
  get_property(IN_LLVMIR_DIR TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_DIR)
  get_property(LINKER_LANGUAGE TARGET ${DEPENDS_TRGT} PROPERTY LINKER_LANGUAGE)
  get_property(LINK_DEPENDS TARGET ${DEPENDS_TRGT} PROPERTY LINK_DEPENDS)
  get_property(LINK_FLAGS TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS)
  get_property(LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE})
  get_property(INTERFACE_LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY INTERFACE_LINK_LIBRARIES)
  get_property(LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE})
  get_property(SHORT_NAME TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_SHORT_NAME)

  if(NOT "${IN_LLVMIR_TYPE}" STREQUAL "${LLVMIR_BINARY_TYPE}" AND
     NOT "${IN_LLVMIR_TYPE}" STREQUAL "${LLVMIR_OBJECT_TYPE}")
    message(FATAL_ERROR "Cannot attach ${TRGT} to a ${IN_LLVMIR_TYPE} target.")
  endif()


  ## main operations
  if(NOT WORK_DIR)
    set(WORK_DIR "${CMAKE_CURRENT_BINARY_DIR}/${LLVMIR_DIR}/${TRGT}")
    file(MAKE_DIRECTORY "${WORK_DIR}")
  endif()

  set(IN_FULL_LLVMIR_FILES "")
  foreach(IN_LLVMIR_FILE ${INFILES})
    list(APPEND IN_FULL_LLVMIR_FILES "${IN_LLVMIR_DIR}/${IN_LLVMIR_FILE}")
  endforeach()

  add_executable(${TRGT} ${IN_FULL_LLVMIR_FILES})
  add_dependencies(${TRGT} ${DEPENDS_TRGT})

  if(SHORT_NAME)
    set_property(TARGET ${TRGT} PROPERTY OUTPUT_NAME ${SHORT_NAME})
  endif()

  # simply setting the property does not seem to work
  #set_property(TARGET ${TRGT}
  #PROPERTY INTERFACE_LINK_LIBRARIES ${INTERFACE_LINK_LIBRARIES})
  #set_property(TARGET ${TRGT}
  #PROPERTY LINK_INTERFACE_LIBRARIES ${LINK_INTERFACE_LIBRARIES})
  #set_property(TARGET ${TRGT}
  #PROPERTY
  #LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}
  #${LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}})

  # FIXME: cmake bags PUBLIC link dependencies under both interface and private
  # target properties, so for an exact propagation it is required to search for
  # elements that are only in the INTERFACE properties and set them as such
  # correctly with the target_link_libraries command
  if(INTERFACE_LINK_LIBRARIES)
    target_link_libraries(${TRGT} PUBLIC ${INTERFACE_LINK_LIBRARIES})
  endif()
  if(LINK_INTERFACE_LIBRARIES)
    target_link_libraries(${TRGT} PUBLIC ${LINK_INTERFACE_LIBRARIES})
  endif()
  if(LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE})
    target_link_libraries(${TRGT} PUBLIC ${LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}})
  endif()

  set_property(TARGET ${TRGT} PROPERTY RUNTIME_OUTPUT_DIRECTORY ${WORK_DIR})
  set_property(TARGET ${TRGT} PROPERTY LINKER_LANGUAGE ${LINKER_LANGUAGE})
  set_property(TARGET ${TRGT} PROPERTY LINK_DEPENDS ${LINK_DEPENDS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS ${LINK_FLAGS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} ${LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY EXCLUDE_FROM_ALL On)
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_SHORT_NAME ${SHORT_NAME})

  # this marks the object as to be linked but not compiled
  foreach(IN_FULL_LLVMIR_FILE ${IN_FULL_LLVMIR_FILES})
    set_property(SOURCE ${IN_FULL_LLVMIR_FILE} PROPERTY EXTERNAL_OBJECT TRUE)
  endforeach()

  ## postamble
endfunction()

#

function(llvmir_attach_library)
  set(options)
  set(oneValueArgs TARGET DEPENDS TYPE OUTPUT_DIR)
  set(multiValueArgs)
  cmake_parse_arguments(LLVMIR_ATTACH
    "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT LLVMIR_ATTACH_TARGET)
    message(FATAL_ERROR "llvmir_attach_library: missing TARGET option")
  endif()
  set(TRGT ${LLVMIR_ATTACH_TARGET})

  if(NOT LLVMIR_ATTACH_DEPENDS)
    message(FATAL_ERROR "llvmir_attach_library: missing DEPENDS option")
  endif()
  set(DEPENDS_TRGT ${LLVMIR_ATTACH_DEPENDS})

  if(NOT LLVMIR_ATTACH_TYPE)
    message(FATAL_ERROR "llvmir_attach_library: missing TYPE option")
  endif()
  set(LIB_TYPE ${LLVMIR_ATTACH_TYPE})

  if(LLVMIR_ATTACH_OUTPUT_DIR)
    if(EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR} AND NOT IS_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
      message(FATAL_ERROR "llvmir_attach_library: OUTPUT must be a directory")
    elseif(NOT EXISTS ${LLVMIR_ATTACH_OUTPUT_DIR})
      file(MAKE_DIRECTORY ${LLVMIR_ATTACH_OUTPUT_DIR})
    endif()
    set(WORK_DIR ${LLVMIR_ATTACH_OUTPUT_DIR})
  endif()

  ## preamble
  llvmir_check_target_properties(${DEPENDS_TRGT})

  get_property(IN_LLVMIR_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_TYPE)
  get_property(LLVMIR_EXTERNAL_TYPE TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_EXTERNAL_TYPE)
  get_property(INFILES TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_FILES)
  get_property(IN_LLVMIR_DIR TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_DIR)
  get_property(LINKER_LANGUAGE TARGET ${DEPENDS_TRGT} PROPERTY LINKER_LANGUAGE)
  get_property(LINK_DEPENDS TARGET ${DEPENDS_TRGT} PROPERTY LINK_DEPENDS)
  get_property(LINK_FLAGS TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS)
  get_property(LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE})
  get_property(INTERFACE_LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY INTERFACE_LINK_LIBRARIES)
  get_property(LINK_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES)
  get_property(LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE} TARGET ${DEPENDS_TRGT} PROPERTY LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE})
  get_property(SHORT_NAME TARGET ${DEPENDS_TRGT} PROPERTY LLVMIR_SHORT_NAME)

  if(NOT "${IN_LLVMIR_TYPE}" STREQUAL "${LLVMIR_BINARY_TYPE}" AND
      NOT "${IN_LLVMIR_TYPE}" STREQUAL "${LLVMIR_OBJECT_TYPE}")
    message(FATAL_ERROR "Cannot attach ${TRGT} to a ${IN_LLVMIR_TYPE} target.")
  endif()


  ## main operations
  if(NOT WORK_DIR)
    set(WORK_DIR "${CMAKE_CURRENT_BINARY_DIR}/${LLVMIR_DIR}/${TRGT}")
    file(MAKE_DIRECTORY "${WORK_DIR}")
  endif()

  set(IN_FULL_LLVMIR_FILES "")
  foreach(IN_LLVMIR_FILE ${INFILES})
    list(APPEND IN_FULL_LLVMIR_FILES "${IN_LLVMIR_DIR}/${IN_LLVMIR_FILE}")
  endforeach()

  add_library(${TRGT} ${LIB_TYPE} ${IN_FULL_LLVMIR_FILES})
  add_dependencies(${TRGT} ${DEPENDS_TRGT})

  if(SHORT_NAME)
    set_property(TARGET ${TRGT} PROPERTY OUTPUT_NAME ${SHORT_NAME})
  endif()

  # simply setting the property does not seem to work
  #set_property(TARGET ${TRGT}
  #PROPERTY INTERFACE_LINK_LIBRARIES ${INTERFACE_LINK_LIBRARIES})
  #set_property(TARGET ${TRGT}
  #PROPERTY LINK_INTERFACE_LIBRARIES ${LINK_INTERFACE_LIBRARIES})
  #set_property(TARGET ${TRGT}
  #PROPERTY
  #LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}
  #${LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}})

  # FIXME: cmake bags PUBLIC link dependencies under both interface and private
  # target properties, so for an exact propagation it is required to search for
  # elements that are only in the INTERFACE properties and set them as such
  # correctly with the target_link_libraries command
  if(INTERFACE_LINK_LIBRARIES)
    target_link_libraries(${TRGT} PUBLIC ${INTERFACE_LINK_LIBRARIES})
  endif()
  if(LINK_INTERFACE_LIBRARIES)
    target_link_libraries(${TRGT} PUBLIC ${LINK_INTERFACE_LIBRARIES})
  endif()
  if(LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE})
    target_link_libraries(${TRGT} PUBLIC ${LINK_INTERFACE_LIBRARIES_${UPPER_CMAKE_BUILD_TYPE}})
  endif()

  set_property(TARGET ${TRGT} PROPERTY LIBRARY_OUTPUT_DIRECTORY ${WORK_DIR})
  set_property(TARGET ${TRGT} PROPERTY ARCHIVE_OUTPUT_DIRECTORY ${WORK_DIR})
  set_property(TARGET ${TRGT} PROPERTY LINKER_LANGUAGE ${LINKER_LANGUAGE})
  set_property(TARGET ${TRGT} PROPERTY LINK_DEPENDS ${LINK_DEPENDS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS ${LINK_FLAGS})
  set_property(TARGET ${TRGT} PROPERTY LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE} ${LINK_FLAGS_${UPPER_CMAKE_BUILD_TYPE}})
  set_property(TARGET ${TRGT} PROPERTY EXCLUDE_FROM_ALL On)
  set_property(TARGET ${TRGT} PROPERTY LLVMIR_SHORT_NAME ${SHORT_NAME})

  # this marks the object as to be linked but not compiled
  foreach(IN_FULL_LLVMIR_FILE ${IN_FULL_LLVMIR_FILES})
    set_property(SOURCE ${IN_FULL_LLVMIR_FILE} PROPERTY EXTERNAL_OBJECT TRUE)
  endforeach()

  ## postamble
endfunction()
