CXX ?= g++
INCLUDES := -Isrc -Igtest/googletest/include -Igtest/googletest -Iabseil

UNAME_S := $(shell uname -s 2>/dev/null)
IS_LINUX := 0
IS_MAC := 0
IS_WINDOWS := 0
ifeq ($(UNAME_S),Linux)
IS_LINUX := 1
else ifeq ($(UNAME_S),Darwin)
IS_MAC := 1
else ifneq (,$(findstring MINGW,$(UNAME_S)))
IS_WINDOWS := 1
else ifneq (,$(findstring MSYS,$(UNAME_S)))
IS_WINDOWS := 1
else ifneq (,$(findstring CYGWIN,$(UNAME_S)))
IS_WINDOWS := 1
else
$(error Unsupported OS: $(UNAME_S). Supported: Linux, macOS, Windows (MinGW/MSYS/CYGWIN). Evaluation is on Spartan (Linux).)
endif
ifeq ($(OS),Windows_NT)
IS_WINDOWS := 1
IS_LINUX := 0
IS_MAC := 0
endif
ifneq ($(IS_LINUX),1)
$(info ============================================================)
$(info  WARNING: not building on Linux (detected: $(UNAME_S)))
$(info  Evaluation runs on SPARTAN (a Linux cluster). Developing)
$(info  fully locally on another OS may result in no marks.)
$(info  Match the SPARTAN toolchain before submitting.)
$(info  On macOS install libomp first: brew install libomp.)
$(info ============================================================)
$(warning non-Linux build: evaluation is on Spartan; developing fully locally may result in no marks)
endif

ifeq ($(IS_LINUX),1)
OPENMP_FLAGS := -fopenmp
THREAD_FLAG := -pthread
EXE :=
TIME_CMD := $(shell command -v /usr/bin/time >/dev/null 2>&1 && echo '/usr/bin/time -f "%e s"' || echo time)
MD5_CMD := md5sum
else ifeq ($(IS_MAC),1)
OMP_DIR ?= /opt/homebrew/opt/libomp
ifeq ($(shell test -d /usr/local/opt/libomp && echo yes),yes)
OMP_DIR := /usr/local/opt/libomp
endif
OPENMP_FLAGS := -Xpreprocessor -fopenmp -I$(OMP_DIR)/include
OPENMP_LIBS := -L$(OMP_DIR)/lib -lomp
THREAD_FLAG := -pthread
EXE :=
TIME_CMD := time
MD5_CMD := md5 -q
else
OPENMP_FLAGS := -fopenmp
THREAD_FLAG := -pthread
EXE := .exe
TIME_CMD := time
MD5_CMD := md5sum
endif

OBJDIR := build
CXXFLAGS := -std=c++17 -Wall -Wextra -O2 $(OPENMP_FLAGS) $(THREAD_FLAG)
ifeq ($(COVERAGE),1)
OBJDIR := build-cov
CXXFLAGS := -std=c++17 -Wall -Wextra -O0 $(OPENMP_FLAGS) $(THREAD_FLAG) --coverage
endif

BIN := bin

LIB_SRCS := $(filter-out src/main.cpp,$(wildcard src/*.cpp))
LIB_OBJS := $(patsubst src/%.cpp,$(OBJDIR)/%.o,$(LIB_SRCS))
MAIN_OBJ := $(OBJDIR)/main.o
TEST_SRCS := $(wildcard tests/*.cpp)
TEST_OBJS := $(patsubst tests/%.cpp,$(OBJDIR)/test_%.o,$(TEST_SRCS))
GTEST_SRCS := gtest/googletest/src/gtest-all.cc
GTEST_OBJS := $(OBJDIR)/gtest-all.o
ABSEIL_SRCS := $(shell find abseil -name '*.cc')
ABSEIL_OBJS := $(patsubst abseil/%.cc,$(OBJDIR)/abseil/%.o,$(ABSEIL_SRCS))

.PHONY: all test coverage smoke run bench clean format check

all: $(BIN)/bpe$(EXE)

$(OBJDIR) $(BIN):
	mkdir -p $@

$(OBJDIR)/%.o: src/%.cpp | $(OBJDIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

$(OBJDIR)/test_%.o: tests/%.cpp | $(OBJDIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

$(OBJDIR)/gtest-all.o: $(GTEST_SRCS) | $(OBJDIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -w -c $< -o $@

$(OBJDIR)/abseil/%.o: abseil/%.cc | $(OBJDIR)
	@mkdir -p $(dir $@)
	$(CXX) -std=c++17 -O2 $(THREAD_FLAG) -w $(INCLUDES) -c $< -o $@

$(BIN)/bpe$(EXE): $(MAIN_OBJ) $(LIB_OBJS) $(ABSEIL_OBJS) | $(BIN)
	$(CXX) $(CXXFLAGS) $(OPENMP_LIBS) $^ -o $@

$(BIN)/bpe_test$(EXE): $(TEST_OBJS) $(LIB_OBJS) $(GTEST_OBJS) $(ABSEIL_OBJS) | $(BIN)
	$(CXX) $(CXXFLAGS) $(OPENMP_LIBS) $^ -o $@

test: $(BIN)/bpe_test$(EXE)
	./$(BIN)/bpe_test$(EXE)

coverage: clean
	$(MAKE) test COVERAGE=1
	@echo
	@echo "=== statement coverage (src/) ==="
	@rm -f /tmp/bpe_cov.txt; \
	for o in build-cov/*.gcno; do \
	  name=$$(basename "$$o" .gcno); \
	  [ -f "src/$$name.cpp" ] || continue; \
	  gcov -o build-cov "$$o" >/dev/null 2>&1; \
	  [ -f "$$name.cpp.gcov" ] || { echo "WARNING: gcov failed for $$name" >&2; continue; }; \
	  awk -v f="src/$$name.cpp" -F: '{c=$$1;gsub(/ /,"",c); if (c ~ /^[0-9]/) {t++; if (c+0>0) e++} else if (c=="#####") {t++}} END{printf "%s %d %d\n", f, e, t}' "$$name.cpp.gcov" >> /tmp/bpe_cov.txt; \
	done; \
	(gcov -o build-cov build-cov/task2_build.gcno >/dev/null 2>&1; cat task2_impl.h.gcov; \
	 gcov -o build-cov build-cov/task2_finalize.gcno >/dev/null 2>&1; cat task2_impl.h.gcov; \
	 gcov -o build-cov build-cov/task2_merge.gcno >/dev/null 2>&1; cat task2_impl.h.gcov) | \
	  awk -F: '{c=$$1;gsub(/ /,"",c); if (c=="#####") total[$$2]=1; else if (c ~ /^[0-9]/) {total[$$2]=1; if (c+0>0) covered[$$2]=1}} END{ht=0; he=0; for (ln in total) {ht++; if (covered[ln]) he++}; printf "src/task2_impl.h %d %d\n", he, ht}' >> /tmp/bpe_cov.txt; \
	awk '{tot+=$$3; exec+=$$2; printf "  %-22s %6.2f%%  (%d/%d)\n", $$1, 100*$$2/$$3, $$2, $$3} END{if (tot==0) {printf "  coverage: FAIL - no instrumented lines found\n"; exit 1} printf "  ----------------------------------------\n"; printf "  TOTAL statements: %d/%d\n", exec, tot; if (exec==tot) {printf "  coverage: 100%% PASS\n"; exit 0} else {printf "  coverage: FAIL - %d uncovered\n", tot-exec; exit 1}}' /tmp/bpe_cov.txt
	@rm -f *.gcov /tmp/bpe_cov.txt

smoke: all
	@./$(BIN)/bpe$(EXE) $(INPUT) 2>/dev/null && \
	  case "$$(basename $(INPUT))" in \
	  test.txt) [ "$$($(MD5_CMD) output.txt | cut -d' ' -f1)" = "ad9bd56b5593db058f4918864ddad7ae" ] && echo "smoke OK: test.txt" || echo "smoke FAIL: test.txt md5 mismatch";; \
	  10M.txt) [ "$$($(MD5_CMD) output.txt | cut -d' ' -f1)" = "437efd507a4ce4ca82956f062fa9c2b2" ] && echo "smoke OK: 10M.txt" || echo "smoke FAIL: 10M.txt md5 mismatch";; \
	  100M.txt) [ "$$($(MD5_CMD) output.txt | cut -d' ' -f1)" = "3581e913ac4c3f85000e8f8c933c8037" ] && echo "smoke OK: 100M.txt" || echo "smoke FAIL: 100M.txt md5 mismatch";; \
	  *) echo "smoke: no locked baseline for $$(basename $(INPUT))";; \
	  esac

run: all
	./$(BIN)/bpe$(EXE) $(INPUT)

bench: all
	@for t in 1 2 4 8 16 32; do \
	  echo "== OMP_NUM_THREADS=$$t =="; \
	  OMP_NUM_THREADS=$$t $(TIME_CMD) ./$(BIN)/bpe$(EXE) $(INPUT); \
	done

clean:
	rm -rf $(BIN) build build-cov *.gcov *.gcda *.gcno

CLANG_FORMAT := $(shell command -v clang-format-14 2>/dev/null || command -v clang-format 2>/dev/null || echo clang-format)
FORMAT_FILES := $(wildcard src/*.cpp) $(wildcard src/*.h) $(wildcard tests/*.cpp)

format:
	$(CLANG_FORMAT) -i --style=file $(FORMAT_FILES)
	@echo "formatted: $(FORMAT_FILES)"

check:
	@echo "clang-format: $$($(CLANG_FORMAT) --version)"
	@if $(CLANG_FORMAT) --dry-run --Werror --style=file $(FORMAT_FILES); then \
	  echo "make check: all files match .clang-format (advisory, not marked)"; \
	else \
	  echo "make check: some files differ from .clang-format - run 'make format' (advisory, not marked)"; \
	fi
