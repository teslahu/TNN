#!/bin/bash

ABI="arm64-v8a"
CLEAN=""
WORK_DIR=`pwd`
FILTER=""
DEVICE_TYPE=""
BUILD_DIR=build
ANDROID_DIR=/data/local/tmp/tnn-benchmark
OUTPUT_LOG_FILE=benchmark_layer_result.txt
LOOP_COUNT=10
ADB=adb

function usage() {
    echo "usage: ./benchmark_layer.sh  [-32] [-c] [-f] <filter-info> [-d] <device-id> [-t] <NAIVE/OPENCL>"
    echo "options:"
    echo "        -32   Build 32 bit."
    echo "        -c    Clean up build folders."
    echo "        -d    run with specified device"
    echo "        -f    specified layer"
    echo "        -t    NAIVE/OPENCL specify the platform to run"
}

function exit_with_msg() {
    echo $1
    exit 1
}

function clean_build() {
    echo $1 | grep "$BUILD_DIR\b" > /dev/null
    if [[ "$?" != "0" ]]; then
        exit_with_msg "Warnning: $1 seems not to be a BUILD folder."
    fi
    rm -rf $1
    mkdir $1
}

function build_android_bench() {
    if [ "-c" == "$CLEAN" ]; then
        clean_build $BUILD_DIR
    fi

    NAIVE=OFF
    if [ "$DEVICE_TYPE" = "NAIVE" ];then
        NAIVE=ON
    fi
    OPENCL=OFF
    if [ "$DEVICE_TYPE" = "OPENCL" ];then
        OPENCL=ON
    fi
    ARM=OFF
    if [ "$DEVICE_TYPE" = "" ];then
        ARM=ON
    fi
    if [ "$DEVICE_TYPE" != "OPENCL" ] && [ "$DEVICE_TYPE" != "NAIVE" ];then
        ARM=ON
    fi

    mkdir -p build
    cd $BUILD_DIR
    cmake ../../.. \
          -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
          -DCMAKE_BUILD_TYPE=Release \
          -DANDROID_ABI="${ABI}" \
          -DANDROID_STL=c++_static \
          -DANDROID_NATIVE_API_LEVEL=android-14  \
          -DANDROID_TOOLCHAIN=clang \
          -DTNN_ARM_ENABLE:BOOL=${ARM} \
          -DTNN_NAIVE_ENABLE:BOOL=${NAIVE} \
          -DTNN_OPENCL_ENABLE:BOOL=${OPENCL} \
          -DTNN_TEST_ENABLE:BOOL=ON \
          -DTNN_UNIT_TEST_ENABLE:BOOL=ON \
          -DTNN_UNIT_TEST_BENCHMARK:BOOL=ON \
          -DTNN_PROFILER_ENABLE:BOOL=ON \
          -DBUILD_FOR_ANDROID_COMMAND=true
    make -j4
}

function bench_android() {
    build_android_bench

    if [ $? != 0 ];then
        exit_with_msg "build failed"
    fi

    $ADB shell "mkdir -p $ANDROID_DIR"
    find . -name "*.so" | while read solib; do
        $ADB push $solib  $ANDROID_DIR
    done
    $ADB push test/unit_test/unit_test $ANDROID_DIR/unit_test
    $ADB shell chmod 0777 $ANDROID_DIR/unit_test

    $ADB shell "getprop ro.product.model > ${ANDROID_DIR}/$OUTPUT_LOG_FILE"
    if [ "$DEVICE_TYPE" != "OPENCL" ] && [ "$DEVICE_TYPE" != "NAIVE" ];then
        DEVICE_TYPE=""
    fi

    if [ "$DEVICE_TYPE" = "" ];then
        $ADB shell "echo '\nbenchmark device: ARM \n' >> ${ANDROID_DIR}/$OUTPUT_LOG_FILE"
        $ADB shell "cd ${ANDROID_DIR}; LD_LIBRARY_PATH=. ./unit_test -ic ${LOOP_COUNT} -dt ARM --gtest_filter="*${FILTER}*" >> $OUTPUT_LOG_FILE"
    fi

    if [ "$DEVICE_TYPE" = "NAIVE" ];then
        $ADB shell "echo '\nbenchmark device: NAIVE \n' >> ${ANDROID_DIR}/$OUTPUT_LOG_FILE"
        $ADB shell "cd ${ANDROID_DIR}; LD_LIBRARY_PATH=. ./unit_test -ic ${LOOP_COUNT} -dt NAIVE --gtest_filter="*${FILTER}*" >> $OUTPUT_LOG_FILE"
    fi

    if [ "$DEVICE_TYPE" = "OPENCL" ];then
        LOOP_COUNT=1
        $ADB shell "echo '\nbenchmark device: OPENCL \n' >> ${ANDROID_DIR}/$OUTPUT_LOG_FILE"
        $ADB shell "cd ${ANDROID_DIR}; LD_LIBRARY_PATH=. ./unit_test -ic ${LOOP_COUNT} -dt OPENCL --gtest_filter="*${FILTER}*" >> $OUTPUT_LOG_FILE"
    fi

    $ADB pull $ANDROID_DIR/$OUTPUT_LOG_FILE ../$OUTPUT_LOG_FILE
    cat ${WORK_DIR}/$OUTPUT_LOG_FILE
}

while [ "$1" != "" ]; do
    case $1 in
        -32)
            shift
            ABI="armeabi-v7a with NEON"
            ;;
        -c)
            shift
            CLEAN="-c"
            ;;
        -f)
            shift
            FILTER=$1
            shift
            ;;
        -d)
            shift
            ADB="adb -s $1"
            shift
            ;;
        -t)
            shift
            DEVICE_TYPE="$1"
            shift
            ;;
        *)
            usage
            exit 1
    esac
done

bench_android
