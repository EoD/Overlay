# Copyright 1999-2013 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/sys-devel/llvm/llvm-9999.ebuild,v 1.38 2013/01/07 20:22:12 voyageur Exp $

EAPI="5"
ABI=x86
inherit git-2 eutils flag-o-matic multilib toolchain-funcs pax-utils

PN="llvm"
P="llvm-9999"
PF="llvm-9999"
PV="9999"

DESCRIPTION="Low Level Virtual Machine"
HOMEPAGE="http://llvm.org/"
SRC_URI=""
EGIT_REPO_URI="git://people.freedesktop.org/~tstellar/llvm"

LICENSE="UoI-NCSA"
SLOT="0"
KEYWORDS="~amd64"
IUSE="debug gold +libffi multitarget ocaml +r600 test udis86 vim-syntax"

DEPEND="dev-lang/perl
	dev-python/docutils
	>=sys-devel/make-3.79
	>=sys-devel/flex-2.5.4
	>=sys-devel/bison-1.875d
	|| ( >=sys-devel/gcc-3.0 >=sys-devel/gcc-apple-4.2.1 )
	|| ( >=sys-devel/binutils-2.18 >=sys-devel/binutils-apple-3.2.3 )
	gold? ( >=sys-devel/binutils-2.22[cxx] )
	libffi? ( virtual/pkgconfig
		app-emulation/emul-linux-x86-baselibs )
	ocaml? ( dev-lang/ocaml )
	udis86? ( dev-libs/udis86-32bit )"
RDEPEND="dev-lang/perl
	libffi? ( app-emulation/emul-linux-x86-baselibs )
	vim-syntax? ( || ( app-editors/vim app-editors/gvim ) )"

S=${WORKDIR}/${P}.src

pkg_setup() {
	# need to check if the active compiler is ok

	broken_gcc=" 3.2.2 3.2.3 3.3.2 4.1.1 "
	broken_gcc_x86=" 3.4.0 3.4.2 "
	broken_gcc_amd64=" 3.4.6 "

	append-flags -m32

	gcc_vers=$(gcc-fullversion)

	if [[ ${broken_gcc} == *" ${version} "* ]] ; then
		elog "Your version of gcc is known to miscompile llvm."
		elog "Check http://www.llvm.org/docs/GettingStarted.html for"
		elog "possible solutions."
		die "Your currently active version of gcc is known to miscompile llvm"
	fi

	if [[ ${CHOST} == i*86-* && ${broken_gcc_x86} == *" ${version} "* ]] ; then
		elog "Your version of gcc is known to miscompile llvm on x86"
		elog "architectures.  Check"
		elog "http://www.llvm.org/docs/GettingStarted.html for possible"
		elog "solutions."
		die "Your currently active version of gcc is known to miscompile llvm"
	fi

	if [[ ${CHOST} == x86_64-* && ${broken_gcc_amd64} == *" ${version} "* ]];
	then
		 elog "Your version of gcc is known to miscompile llvm in amd64"
		 elog "architectures.  Check"
		 elog "http://www.llvm.org/docs/GettingStarted.html for possible"
		 elog "solutions."
		die "Your currently active version of gcc is known to miscompile llvm"
	 fi
}

src_prepare() {
	PN="llvm"
	P="llvm-9999"
	# unfortunately ./configure won't listen to --mandir and the-like, so take
	# care of this.
	einfo "Fixing install dirs"
	sed -e 's,^PROJ_docsdir.*,PROJ_docsdir := $(PROJ_prefix)/share/doc/'${PF}, \
		-e 's,^PROJ_etcdir.*,PROJ_etcdir := '"${EPREFIX}"'/etc/llvm,' \
		-e 's,^PROJ_libdir.*,PROJ_libdir := $(PROJ_prefix)/'lib32/${PN}, \
		-i Makefile.config.in || die "Makefile.config sed failed"
	sed -e "/ActiveLibDir = ActivePrefix/s/lib/lib32\/${PN}/" \
		-i tools/llvm-config/llvm-config.cpp || die "llvm-config sed failed"

	einfo "Fixing rpath and CFLAGS"
	sed -e 's,\$(RPATH) -Wl\,\$(\(ToolDir\|LibDir\)),$(RPATH) -Wl\,'"${EPREFIX}"/usr/lib32/${PN}, \
		-e '/OmitFramePointer/s/-fomit-frame-pointer//' \
		-i Makefile.rules || die "rpath sed failed"
	if use gold; then
		sed -e 's,\$(SharedLibDir),'"${EPREFIX}"/usr/lib32/${PN}, \
			-i tools/gold/Makefile || die "gold rpath sed failed"
	fi

	epatch "${FILESDIR}"/${PN}-3.2-nodoctargz.patch
	epatch "${FILESDIR}"/${PN}-3.0-PPC_macro.patch

	# User patches
	epatch_user
}

src_configure() {
	local CONF_FLAGS="--enable-shared
		--with-optimize-option=
		$(use_enable !debug optimized)
		$(use_enable debug assertions)
		$(use_enable debug expensive-checks)"

	if use multitarget; then
		CONF_FLAGS="${CONF_FLAGS} --enable-targets=all"
	else
		CONF_FLAGS="${CONF_FLAGS} --enable-targets=host,cpp"
	fi

	if use amd64; then
		CONF_FLAGS="${CONF_FLAGS} --enable-pic"
	fi

	if use r600; then
		CONF_FLAGS="${CONF_FLAGS} --enable-experimental-targets=R600"
	fi

	if use gold; then
		CONF_FLAGS="${CONF_FLAGS} --with-binutils-include=${EPREFIX}/usr/include/"
	fi
	if use ocaml; then
		CONF_FLAGS="${CONF_FLAGS} --enable-bindings=ocaml"
	else
		CONF_FLAGS="${CONF_FLAGS} --enable-bindings=none"
	fi

	if use udis86; then
		CONF_FLAGS="${CONF_FLAGS} --with-udis86"
	fi

	if use libffi; then
		append-cppflags "$(pkg-config --cflags libffi)"
	fi
	CONF_FLAGS="${CONF_FLAGS} $(use_enable libffi)"

	# llvm prefers clang over gcc, so we may need to force that
	tc-export CC CXX
	econf ${CONF_FLAGS}
}

src_compile() {
	emake VERBOSE=1 KEEP_SYMBOLS=1 REQUIRES_RTTI=1

	pax-mark m Release/bin/lli
	if use test; then
		pax-mark m unittests/ExecutionEngine/JIT/Release/JITTests
	fi
}

src_install() {
	emake KEEP_SYMBOLS=1 DESTDIR="${D}" install

	if use vim-syntax; then
		insinto /usr/share/vim/vimfiles/syntax
		doins utils/vim/*.vim
	fi

	# Fix install_names on Darwin.  The build system is too complicated
	# to just fix this, so we correct it post-install
	local lib= f= odylib= libpv=${PV}
	if [[ ${CHOST} == *-darwin* ]] ; then
		eval $(grep PACKAGE_VERSION= configure)
		[[ -n ${PACKAGE_VERSION} ]] && libpv=${PACKAGE_VERSION}
		for lib in lib{EnhancedDisassembly,LLVM-${libpv},LTO,profile_rt}.dylib {BugpointPasses,LLVMHello}.dylib ; do
			# libEnhancedDisassembly is Darwin10 only, so non-fatal
			[[ -f ${ED}/usr/lib/${PN}/${lib} ]] || continue
			ebegin "fixing install_name of $lib"
			install_name_tool \
				-id "${EPREFIX}"/usr/lib/${PN}/${lib} \
				"${ED}"/usr/lib/${PN}/${lib}
			eend $?
		done
		for f in "${ED}"/usr/bin/* "${ED}"/usr/lib/${PN}/libLTO.dylib ; do
			odylib=$(scanmacho -BF'%n#f' "${f}" | tr ',' '\n' | grep libLLVM-${libpv}.dylib)
			ebegin "fixing install_name reference to ${odylib} of ${f##*/}"
			install_name_tool \
				-change "${odylib}" \
					"${EPREFIX}"/usr/lib/${PN}/libLLVM-${libpv}.dylib \
				"${f}"
			eend $?
		done
	fi

	mv "${D}"/usr/bin/llvm-config "${D}"/usr/bin/llvm-config32 || die "Removing files failed."
	rm -rf "${D}"/usr/share || die "Removing files failed."
	rm -rf "${D}"/usr/bin/bugpoint || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llc || die "Removing files failed."
	rm -rf "${D}"/usr/bin/lli || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-ar || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-as || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-bcanalyzer || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-cov || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-diff || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-dis || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-dwarfdump || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-extract || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-link || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-mc || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-mcmarkup || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-nm || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-objdump || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-prof || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-ranlib || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-readobj || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-rtdyld || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-size || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-stress || die "Removing files failed."
	rm -rf "${D}"/usr/bin/llvm-tblgen || die "Removing files failed."
	rm -rf "${D}"/usr/bin/macho-dump || die "Removing files failed."
	rm -rf "${D}"/usr/bin/opt || die "Removing files failed."
	rm -rf "${D}"/usr/include || die "Removing files failed."
}
