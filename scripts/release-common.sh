#!/bin/bash
#
# This script creates a binary release of OpenSCAD.
#
# By default, it builds a package for the same system it is run on. It
# can also cross-build packages for other systems when the
# OPENSCAD_BUILD_TARGET_OSTYPE environment variable is set.
#
# By default, the script will create a file called
# openscad-<versionstring>.<extension> in the current directory. When
# cross-building, the file will be under a directory with the triple-name
# of the target system, for example ./x86_64-w64-mingw32
#
# Targets can have special functions via naming convetion and run().
# example 1: If our target ostype is linux-gnu, and we call "run build", then
# if build_linux-gnu() is defined, it is called, otherwise build() is called
# example 2: If our target ostype is darwin, and we call "run clean", then
# if clean_darwin() is defined, it is called, otherwise clean() is called

printUsage()
{
  echo "Usage: release-common.sh [-v <versionstring>] [-d <versiondate>] -c"
  echo ""
  echo " -v  Version string (e.g. -v 2010.01)"
  echo " -d  Version date (e.g. -d 2010.01.23)"
  echo " -snapshot Build a snapshot binary (make e.g. experimental features "
  echo "     available, build with commit info)"
  echo
  echo "If no version string or version date is given, todays date will be used"
  echo "(YYYY-MM-DD) If only version date is given, it will be used also as"
  echo "version string. If no make target is given, none will be used"
  echo "on Mac OS X"
  echo
  echo "  Example: $0 -v 2010.01"
  paralell_note
}

paralell_note()
{
  if [ ! $NUMCPU ]; then
    echo "note: you can 'export NUMCPU=x' for multi-core compiles (x=number)";
    NUMCPU=1
  fi
}

run()
{
  # run() calls function $1 specialized for our target $2. or the generic $1.
  # see top of this file for some examples.
  # http://stackoverflow.com/questions/85880/determine-if-a-function-exists-in-bash
  runfunc1=`echo $1"_"$OPENSCAD_BUILD_TARGET_OSTYPE`
  runfunc2=`echo $1`
  if [ "`type -t $runfunc1 | grep function`" ]; then
    echo "calling $runfunc1"
    eval $runfunc1
  elif [ "`type -t $runfunc2 | grep function`" ]; then
    echo "calling $runfunc2"
    eval $runfunc2
  else
    echo "$runfunc2 not defined for target $OPENSCAD_BUILD_TARGET_OSTYPE. skipping."
  fi
}

check_prereq_mxe()
{
  MAKENSIS=
  if [ "`command -v makensis`" ]; then
    MAKENSIS=makensis
  elif [ "`command -v i686-pc-mingw32-makensis`" ]; then
    # we cant find systems nsis so look for the MXE's 32 bit version.
    MAKENSIS=i686-pc-mingw32-makensis
  else
    echo "makensis not found. please install nsis on your system."
    echo "(for example, on debian linux, try apt-get install nsis)"
    exit 1
  fi
}

update_mcad()
{
  if [ ! -e $OPENSCADDIR/libraries/MCAD/__init__.py ]; then
    echo "Downloading MCAD"
    git submodule init
    git submodule update
  else
    echo "MCAD found:" $OPENSCADDIR/libraries/MCAD
  fi
  if [ -d .git ]; then
    git submodule update
  fi
}

verify_binary_mxe()
{
  cd $DEPLOYDIR
  if [ ! -e $MAKE_TARGET/openscad.com ]; then
    echo "cant find $MAKE_TARGET/openscad.com. build failed. stopping."
    exit 1
  fi
  if [ ! -e $MAKE_TARGET/openscad.exe ]; then
    echo "cant find $MAKE_TARGET/openscad.exe. build failed. stopping."
    exit 1
  fi
  cd $OPENSCADDIR
}

verify_binary_linux-gnu()
{
  if [ ! -e $MAKE_TARGET/openscad ]; then
    echo "cant find $MAKE_TARGET/openscad. build failed. stopping."
    exit 1
  fi
}

if [ "`echo $* | grep snapshot`" ]; then
  CONFIG="$CONFIG snapshot experimental"
  OPENSCAD_COMMIT=`git log -1 --pretty=format:"%h"`
fi

setup_directories_darwin()
{
  EXAMPLESDIR=OpenSCAD.app/Contents/Resources/examples
  LIBRARYDIR=OpenSCAD.app/Contents/Resources/libraries
  FONTDIR=OpenSCAD.app/Contents/Resources/fonts
  TRANSLATIONDIR=OpenSCAD.app/Contents/Resources/locale
  COLORSCHEMESDIR=OpenSCAD.app/Contents/Resources/color-schemes
}

setup_directories_mxe()
{
  cd $OPENSCADDIR
  EXAMPLESDIR=$DEPLOYDIR/openscad-$VERSION/examples/
  LIBRARYDIR=$DEPLOYDIR/openscad-$VERSION/libraries/
  FONTDIR=$DEPLOYDIR/openscad-$VERSION/fonts/
  TRANSLATIONDIR=$DEPLOYDIR/openscad-$VERSION/locale/
  COLORSCHEMESDIR=$DEPLOYDIR/openscad-$VERSION/color-schemes/
  rm -rf $DEPLOYDIR/openscad-$VERSION
  mkdir $DEPLOYDIR/openscad-$VERSION
}

setup_directories_linux-gnu()
{
  EXAMPLESDIR=openscad-$VERSION/examples/
  LIBRARYDIR=openscad-$VERSION/libraries/
  FONTDIR=openscad-$VERSION/fonts/
  TRANSLATIONDIR=openscad-$VERSION/locale/
  COLORSCHEMESDIR=openscad-$VERSION/color-schemes/
  rm -rf openscad-$VERSION
  mkdir openscad-$VERSION
}

copy_examples()
{
  echo $EXAMPLESDIR
  mkdir -p $EXAMPLESDIR
  rm -f examples.tar
  tar cf examples.tar examples
  cd $EXAMPLESDIR/.. && tar xf $OPENSCADDIR/examples.tar && cd $OPENSCADDIR
  rm -f examples.tar
  chmod -R 644 $EXAMPLESDIR/*/*
}

copy_fonts_common()
{
  echo $FONTDIR
  mkdir -p $FONTDIR
  cp -a fonts/10-liberation.conf $FONTDIR
  cp -a fonts/Liberation-2.00.1 $FONTDIR
}

copy_fonts()
{
  copy_fonts_common
}

copy_fonts_darwin()
{
  copy_fonts_common
  cp -a fonts/05-osx-fonts.conf $FONTDIR
  cp -a fonts-osx/* $FONTDIR
}

copy_fonts_mxe()
{
  copy_fonts_common
  cp -a $MXETARGETDIR/etc/fonts/ "$FONTDIR"
}

copy_colorschemes()
{
  echo $COLORSCHEMESDIR
  mkdir -p $COLORSCHEMESDIR
  cp -a color-schemes/* $COLORSCHEMESDIR
}

copy_mcad()
{
  echo $LIBRARYDIR
  mkdir -p $LIBRARYDIR
  # exclude the .git stuff from MCAD which is a git submodule.
  # tar is a relatively portable way to do exclusion, without the
  # risks of rm
  rm -f libraries.tar
  tar cf libraries.tar --exclude=.git* libraries
  cd $LIBRARYDIR/.. && tar xf $OPENSCADDIR/libraries.tar && cd $OPENSCADDIR
  rm -f libraries.tar
  chmod -R u=rwx,go=r,+X $LIBRARYDIR/*
}

copy_translations()
{
  echo $TRANSLATIONDIR
  mkdir -p $TRANSLATIONDIR
  cd locale && tar cvf $OPENSCADDIR/translations.tar */*/*.mo && cd $OPENSCADDIR
  cd $TRANSLATIONDIR && tar xvf $OPENSCADDIR/translations.tar && cd $OPENSCADDIR
  rm -f translations.tar
}

create_archive_darwin()
{

  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSIONDATE" OpenSCAD.app/Contents/Info.plist
  macdeployqt OpenSCAD.app -dmg -no-strip
  mv OpenSCAD.dmg OpenSCAD-$VERSION.dmg
  hdiutil internet-enable -yes -quiet OpenSCAD-$VERSION.dmg
  echo "Binary created: OpenSCAD-$VERSION.dmg"
}

create_archive_msys()
{
  cd $OPENSCADDIR
  cd $DEPLOYDIR

  echo "QT5 deployment, dll and other files copying..."
  windeployqt $TARGET/openscad.exe

  bits=64
  if [ $OPENSCAD_BUILD_TARGET_ARCH = i686 ]; then
    bits=32
  fi

  flprefix=/mingw$bits/bin/
  echo MSYS2, dll copying...
  echo from $flprefix
  echo to $DEPLOYDIR/$TARGET
  flist=
  fl="$fl libboost_filesystem-mt.dll"
  fl="$fl libboost_program_options-mt.dll"
  fl="$fl libboost_regex-mt.dll"
  fl="$fl libboost_system-mt.dll"
  fl="$fl libboost_thread-mt.dll"
  fl="$fl glew32.dll"
  # fl="$fl opengl.dll"
  fl="$fl qscintilla2.dll"
  fl="$fl libgmp-10.dll"
  fl="$fl libgmpxx-4.dll"
  # fl="$fl libmpfr.dll"
  fl="$fl libopencsg-1.dll"
  fl="$fl libCGAL.dll"
  fl="$fl libCGAL_Core.dll"
  fl="$fl libharfbuzz-0.dll"
  fl="$fl libharfbuzz-gobject-0.dll"
  fl="$fl libglib-2.0-0.dll"
  fl="$fl libfontconfig-1.dll"
  fl="$fl libexpat-1.dll"
  fl="$fl libbz2-1.dll"
  fl="$fl libintl-8.dll"
  fl="$fl libiconv-2.dll"
  fl="$fl libfreetype-6.dll"
  fl="$fl libpcre16-0.dll"
  fl="$fl zlib1.dll"
  fl="$fl libpng16-16.dll"
  fl="$fl libicudt55.dll"
  fl="$fl Qt5PrintSupport.dll"
  for dllfile in $fl; do
    if [ -e $flprefix/$dllfile ]; then
      echo $flprefix/$dllfile
      cp $flprefix/$dllfile $DEPLOYDIR/$TARGET/
    else
      echo cannot find $flprefix/$dllfile
      echo stopping build.
      exit 1
    fi
  done

  ARCH_INDICATOR=Msys2-x86-64
  if [ $OPENSCAD_BUILD_TARGET_ARCH = i686 ]; then
    ARCH_INDICATOR=Msys2-x86-32
  fi
  BINFILE=$DEPLOYDIR/OpenSCAD-$VERSION-$ARCH_INDICATOR.zip
  INSTFILE=$DEPLOYDIR/OpenSCAD-$VERSION-$ARCH_INDICATOR-Installer.exe

  echo
  echo "Copying main binary .exe, .com, and dlls"
  echo "from $DEPLOYDIR/$TARGET"
  echo "to $DEPLOYDIR/openscad-$VERSION"
  TMPTAR=$DEPLOYDIR/windeployqt.tar
  cd $DEPLOYDIR
  cd $TARGET
  tar cvf $TMPTAR --exclude=winconsole.o .
  cd $DEPLOYDIR
  cd ./openscad-$VERSION
  tar xvf $TMPTAR
  cd $DEPLOYDIR
  rm -f $TMPTAR

  echo "Creating zipfile..."
  rm -f OpenSCAD-$VERSION.x86-$ARCH.zip
  "$ZIP" $ZIPARGS $BINFILE openscad-$VERSION
  cd $OPENSCADDIR
  echo "Binary zip package created:"
  echo "  $BINFILE"
  echo "Not creating installable .msi/.exe package"
}

create_archive_mxe()
{
  cd $OPENSCADDIR
  cd $DEPLOYDIR

  # try to use a package filename that is not confusing (i686-w64-mingw32 is)
  ARCH_INDICATOR=MingW-x86-32
  if [ $OPENSCAD_BUILD_TARGET_ARCH = x86_64 ]; then
    ARCH_INDICATOR=MingW-x86-64
  fi

  BINFILE=$DEPLOYDIR/OpenSCAD-$VERSION-$ARCH_INDICATOR.zip
  INSTFILE=$DEPLOYDIR/OpenSCAD-$VERSION-$ARCH_INDICATOR-Installer.exe

  #package
  if [ $MXELIBTYPE = "shared" ]; then
    flprefix=$DEPLOYDIR/$MXE_TARGET_DIR/bin
    echo Copying dlls for shared library build
    echo from $flprefix
    echo to $DEPLOYDIR/$MAKE_TARGET
    flist=
    # fl="$fl opengl.dll" # use Windows version?
    fl="$fl libgcc_s_seh-1.dll"
    #fl="$fl libmpfr-4.dll" #mpfr doesnt have a shared lib. linked static
    fl="$fl libpcre-1.dll"
    fl="$fl libgmp-10.dll"
    fl="$fl libgmpxx-4.dll"
    fl="$fl libboost_filesystem-mt.dll"
    fl="$fl libboost_program_options-mt.dll"
    fl="$fl libboost_regex-mt.dll"
    fl="$fl libboost_chrono-mt.dll"
    fl="$fl libboost_system-mt.dll"
    fl="$fl libboost_thread_win32-mt.dll"
    fl="$fl libCGAL.dll"
    fl="$fl libCGAL_Core.dll"
    fl="$fl GLEW.dll"
    fl="$fl libglib-2.0-0.dll"
    fl="$fl libopencsg-1.dll"
    fl="$fl libharfbuzz-0.dll"
    # fl="$fl libharfbuzz-gobject-0.dll" # ????
    fl="$fl libfontconfig-1.dll"
    fl="$fl libexpat-1.dll"
    fl="$fl libbz2.dll"
    fl="$fl libintl-8.dll"
    fl="$fl libiconv-2.dll"
    fl="$fl libfreetype-6.dll"
    fl="$fl libpcre16-0.dll"
    fl="$fl zlib1.dll"
    fl="$fl libpng16-16.dll"
    fl="$fl icudt54.dll"
    fl="$fl icudt.dll"
    fl="$fl icuin.dll"
    fl="$fl libstdc++-6.dll"
    fl="$fl ../qt5/lib/qscintilla2.dll"
    fl="$fl ../qt5/bin/Qt5PrintSupport.dll"
    fl="$fl ../qt5/bin/Qt5Core.dll"
    fl="$fl ../qt5/bin/Qt5Gui.dll"
    fl="$fl ../qt5/bin/Qt5OpenGL.dll"
    #  fl="$fl ../qt5/bin/QtSvg4.dll" # why is this here?
    fl="$fl ../qt5/bin/Qt5Widgets.dll"
    fl="$fl ../qt5/bin/Qt5PrintSupport.dll"
    fl="$fl ../qt5/bin/Qt5PrintSupport.dll"
    for dllfile in $fl; do
    if [ -e $flprefix/$dllfile ]; then
    echo $flprefix/$dllfile
    cp $flprefix/$dllfile $DEPLOYDIR/$MAKE_TARGET/
    else
    echo cannot find $flprefix/$dllfile
    echo stopping build.
    exit 1
    fi
    done
  fi

  echo "Copying main binary .exe, .com, and other stuff"
  echo "from $DEPLOYDIR/$MAKE_TARGET"
  echo "to $DEPLOYDIR/openscad-$VERSION"
  TMPTAR=$DEPLOYDIR/tmpmingw.$OPENSCAD_BUILD_TARGET_ARCH.$MXELIBTYPE.tar
  cd $DEPLOYDIR
  cd $MAKE_TARGET
  tar cvf $TMPTAR --exclude=winconsole.o .
  cd $DEPLOYDIR
  cd ./openscad-$VERSION
  tar xf $TMPTAR
  cd $DEPLOYDIR
  rm -f $TMPTAR


  echo "Creating binary zip package `basename $BINFILE`"
  rm -f $BINFILE
  "$ZIP" $ZIPARGS $BINFILE openscad-$VERSION
  cd $OPENSCADDIR

  echo "Creating installer `basename $INSTFILE`"
  echo "Copying NSIS files to $DEPLOYDIR/openscad-$VERSION"
  cp ./scripts/installer$OPENSCAD_BUILD_TARGET_ARCH.nsi $DEPLOYDIR/openscad-$VERSION/installer_arch.nsi
  cp ./scripts/installer.nsi $DEPLOYDIR/openscad-$VERSION/
  cp ./scripts/mingw-file-association.nsh $DEPLOYDIR/openscad-$VERSION/
  cp ./scripts/x64.nsh $DEPLOYDIR/openscad-$VERSION/
  cp ./scripts/LogicLib.nsh $DEPLOYDIR/openscad-$VERSION/
  cd $DEPLOYDIR/openscad-$VERSION
  NSISDEBUG=-V2
  # NSISDEBUG=    # leave blank for full log
  echo $MAKENSIS $NSISDEBUG "-DVERSION=$VERSION" installer.nsi
  $MAKENSIS $NSISDEBUG "-DVERSION=$VERSION" installer.nsi
  cp $DEPLOYDIR/openscad-$VERSION/openscad_setup.exe $INSTFILE
  cd $OPENSCADDIR
}

create_archive_linux-gnu()
{
  # Do stuff from release-linux.sh
  mkdir openscad-$VERSION/bin
  mkdir -p openscad-$VERSION/lib/openscad
  cp scripts/openscad-linux openscad-$VERSION/bin/openscad
  cp openscad openscad-$VERSION/lib/openscad/
  if [[ $OPENSCAD_BUILD_TARGET_ARCH == x86_64 ]]; then
      gcc -o chrpath_linux -DSIZEOF_VOID_P=8 scripts/chrpath_linux.c
  else
      gcc -o chrpath_linux -DSIZEOF_VOID_P=4 scripts/chrpath_linux.c
  fi
  ./chrpath_linux -d openscad-$VERSION/lib/openscad/openscad

  QTLIBDIR=$(dirname $(ldd openscad | grep Qt5Gui | head -n 1 | awk '{print $3;}'))
   ( ldd openscad ; ldd "$QTLIBDIR"/qt5/plugins/platforms/libqxcb.so ) \
   | sed -re 's,.* => ,,; s,[\t ].*,,;' -e '/^$/d' -e '/libc\.so|libm\.so|libdl\.so|libgcc_|libpthread\.so/d' \
   | sort -u \
   | xargs cp -vt "openscad-$VERSION/lib/openscad/"
  PLATFORMDIR="openscad-$VERSION/lib/openscad/platforms/"
  mkdir -p "$PLATFORMDIR"
  cp -av "$QTLIBDIR"/qt5/plugins/platforms/libqxcb.so "$PLATFORMDIR"
  DRIDRIVERDIR=$(find /usr/lib -xdev -type d -name dri)
  if [ -d "$DRIDRIVERDIR" ]
    then
      DRILIB="openscad-$VERSION/lib/openscad/dri/"
      mkdir -p "$DRILIB"
      cp -av "$DRIDRIVERDIR"/swrast_dri.so "$DRILIB"
    fi

  strip openscad-$VERSION/lib/openscad/*
  mkdir -p openscad-$VERSION/share/appdata
	cp icons/openscad.{desktop,png,xml} openscad-$VERSION/share/appdata
  cp scripts/installer-linux.sh openscad-$VERSION/install.sh
  chmod 755 -R openscad-$VERSION/
  PACKAGEFILE=openscad-$VERSION.$OPENSCAD_BUILD_TARGET_ARCH.tar.gz
  tar cz openscad-$VERSION > $PACKAGEFILE
  echo
  echo "Binary created:" $PACKAGEFILE
  echo
}

setup_misc()
{
  MAKE_TARGET=
  # for QT4 set QT_SELECT=4
  QT_SELECT=5
  export QT_SELECT
}

setup_misc_mxe()
{
  MAKE_TARGET=release
  ZIP="zip"
  ZIPARGS="-r -q"
}

setup_misc_msys()
{
  setup_misc_mxe
}

qmaker()
{
  QMAKE="`command -v qmake-qt5`"
  if [ ! -x "$QMAKE" ]; then
    QMAKE=qmake
  fi
  "$QMAKE" VERSION=$VERSION OPENSCAD_COMMIT=$OPENSCAD_COMMIT CONFIG+="$CONFIG" CONFIG-=debug openscad.pro
}

qmaker_msys()
{
  cd $DEPLOYDIR
  echo qmake VERSION=$VERSION OPENSCAD_COMMIT=$OPENSCAD_COMMIT CONFIG+="$CONFIG" CONFIG-=debug ../openscad.pro
  qmake VERSION=$VERSION OPENSCAD_COMMIT=$OPENSCAD_COMMIT CONFIG+="$CONFIG" CONFIG-=debug ../openscad.pro
  cd $OPENSCADDIR
}

qmaker_mxe()
{
  cd $DEPLOYDIR
  MINGWCONFIG=mingw-cross-env
  if [ $OPENSCAD_BUILD_TARGET_ABI = "shared" ]; then
    MINGWCONFIG=mingw-cross-env-shared
  fi
  qmake VERSION=$VERSION OPENSCAD_COMMIT=$OPENSCAD_COMMIT CONFIG+="$CONFIG" CONFIG+=$MINGWCONFIG CONFIG-=debug ../openscad.pro
  cd $OPENSCADDIR
}

make_clean_mxe()
{
  cd $DEPLOYDIR
  make clean
  rm -f ./release/*
  rm -f ./debug/*
  cd $OPENSCADDIR
}

make_clean_msys()
{
  make_clean_mxe
}

make_clean_darwin()
{
  make -s clean
  rm -rf OpenSCAD.app
}

make_clean_linux-gnu()
{
  make -s clean
}

touch_parser_lexer_mxe()
{
  # kludge to enable paralell make
  touch -t 200012121010 $OPENSCADDIR/src/parser_yacc.h
  touch -t 200012121010 $OPENSCADDIR/src/parser_yacc.cpp
  touch -t 200012121010 $OPENSCADDIR/src/parser_yacc.hpp
  touch -t 200012121010 $OPENSCADDIR/src/lexer_lex.cpp
}

touch_parser_lexer_msys()
{
  touch_parser_lexer_mxe
}

build_gui_binary()
{
  make -j$NUMCPU $MAKE_TARGET
  if [[ $? != 0 ]]; then
    echo "Error building OpenSCAD. Aborting."
    exit 1
  fi
}

build_gui_binary_mxe()
{
  # make main openscad.exe
  cd $DEPLOYDIR
  make $MAKE_TARGET -j$NUMCPU
  # make console pipe-able openscad.com - see winconsole.pro for info
  qmake ../winconsole/winconsole.pro
  make
  cd $OPENSCADDIR
}

build_gui_binary_msys()
{
  build_gui_binary_mxe()
}

OPENSCADDIR=$PWD
if [ ! -f $OPENSCADDIR/openscad.pro ]; then
  echo "Must be run from the OpenSCAD source root directory"
  exit 1
fi

CONFIG=deploy

if [ ! $OPENSCAD_BUILD_TARGET_OSTYPE ]; then
  OPENSCAD_BUILD_TARGET_OSTYPE=$OSTYPE
fi
if [ ! $OPENSCAD_BUILD_TARGET_ARCH ]; then
  OPENSCAD_BUILD_TARGET_ARCH=`uname -m`
fi

case "$OPENSCAD_BUILD_TARGET_OSTYPE" in
  msys|darwin|linux-gnu|mxe)
    echo "build target ostype: $OPENSCAD_BUILD_TARGET_OSTYPE"
    ;;
  *)
    echo "build target ostype not familiar. please edit $0"
    exit
    ;;
esac

if [ "`echo $* | grep snapshot`" ]; then
  CONFIG="$CONFIG snapshot experimental"
  OPENSCAD_COMMIT=`git log -1 --pretty=format:"%h"`
fi

while getopts 'v:d:c' c
do
  case $c in
  v) VERSION=$OPTARG;;
  d) VERSIONDATE=$OPTARG;;
  esac
done

if test -z "$VERSIONDATE"; then
  VERSIONDATE=`date "+%Y.%m.%d"`
fi
if test -z "$VERSION"; then
  VERSION=$VERSIONDATE
fi

export VERSIONDATE
export VERSION

echo "Building openscad-$VERSION ($VERSIONDATE) $CONFIG..."
run check_prereq
paralell_note
echo "NUMCPU: " $NUMCPU
run update_mcad
run setup_misc
run qmaker
run make_clean
run touch_parser_lexer
run build_gui_binary
run verify_binary
run setup_directories
if [ -n $EXAMPLESDIR ]; then run copy_examples ; fi
if [ -n $FONTSDIR ]; then run copy_fonts ; fi
if [ -n $COLORSCHEMESDIR ]; then run copy_colorschemes ; fi
if [ -n $LIBRARYDIR ]; then run copy_mcad ; fi
if [ -n $TRANSLATIONDIR ]; then run copy_translations ; fi
run create_archive

