module Main (tests, main) where

import           Prelude hiding (FilePath)

import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as B8
import           Data.List (intercalate)
import qualified Data.Text as T
import qualified Test.Framework as F
import           Test.Framework.Providers.HUnit (testCase)
import           Test.Framework.Providers.QuickCheck2 (testProperty)
import           Test.HUnit (Assertion, assert, (@?=))
import           Test.QuickCheck

import           Filesystem.Path as P
import           Filesystem.Path.CurrentOS ()
import           Filesystem.Path.Rules

main :: IO ()
main = F.defaultMain tests

tests :: [F.Test]
tests =
	[ F.testGroup "Basic properties"
	  [ testNull
	  , testRoot
	  , testDirectory
	  , testParent
	  , testFilename
	  , testBasename
	  , testAbsolute
	  , testRelative
	  ]
	
	, F.testGroup "Basic operations"
	  [ testAppend
	  , testCommonPrefix
	  , testSplitExtension
	  , testCollapse
	  ]
	
	, F.testGroup "To/From bytes"
	  [ testIdentity "POSIX" posix posixPaths
	  , testIdentity "Windows" windows windowsPaths
	  , testMixedValidityToBytes
	  ]
	
	, F.testGroup "To/From text"
	  [ testToText
	  , testFromText
	  ]
	
	, F.testGroup "Validity"
	  [ testProperty "POSIX" $ forAll posixPaths $ valid posix
	  , testProperty "Windows" $ forAll windowsPaths $ valid windows
	  ]
	
	, testSplitSearchPath
	, testParsing
	]

testCases :: F.TestName -> [Assertion] -> F.Test
testCases name = F.testGroup name . zipWith (\n -> testCase n . assert) labels where
	labels = map show $ iterate (+ 1) 1

testNull :: F.Test
testNull = testCases "null"
	[ assert (P.null empty)
	, toChar8 posix empty @?= ""
	, toString windows empty @?= ""
	]

testRoot :: F.Test
testRoot =
	let t x y = toChar8 posix (root (fromChar8 posix x)) @?= y in
	
	testCases "root"
	[ t "" ""
	, t "/" "/"
	, t "foo" ""
	, t "/foo" "/"
	]

testDirectory :: F.Test
testDirectory =
	let t x y = toChar8 posix (directory (fromChar8 posix x)) @?= y in
	
	testCases "directory"
	[ t "" "./"
	, t "/" "/"
	, t "/foo/bar" "/foo/"
	, t "/foo/bar/" "/foo/bar/"
	, t "." "./"
	, t ".." "../"
	, t "../foo" "../"
	, t "../foo/" "../foo/"
	, t "foo" "./"
	, t "foo/bar" "./foo/"
	]

testParent :: F.Test
testParent =
	let t x y = toChar8 posix (parent (fromChar8 posix x)) @?= y in
	
	testCases "parent"
	[ t "" "./"
	, t "/" "/"
	, t "/foo/bar" "/foo/"
	, t "/foo/bar/" "/foo/"
	, t "." "./"
	, t ".." "./"
	, t "../foo/bar" "../foo/"
	, t "../foo/bar" "../foo/"
	, t "foo" "./"
	, t "foo/bar" "./foo/"
	]

testFilename :: F.Test
testFilename =
	let t x y = toChar8 posix (filename (fromChar8 posix x)) @?= y in
	
	testCases "filename"
	[ t "" ""
	, t "/" ""
	, t "/foo/" ""
	, t "/foo/bar" "bar"
	, t "/foo/bar.txt" "bar.txt"
	]

testBasename :: F.Test
testBasename =
	let tp x y = toChar8 posix (basename (fromChar8 posix x)) @?= y in
	let tw x y = toString windows (basename (fromString windows x)) @?= y in
	
	testCases "basename"
	[ tp "/foo/bar" "bar"
	, tp "/foo/bar.txt" "bar"
	, tp "." ""
	, tp ".." ""
	
	, tw "c:\\foo\\bar" "bar"
	, tw "c:\\foo\\bar.txt" "bar"
	, tw "." ""
	, tw ".." ""
	]

testAbsolute :: F.Test
testAbsolute = testCases "absolute"
	[ assert $ absolute (fromChar8 posix "/")
	, assert $ absolute (fromChar8 posix "/foo/bar")
	, assert . not $ absolute (fromChar8 posix "")
	, assert . not $ absolute (fromChar8 posix "foo/bar")
	]

testRelative :: F.Test
testRelative = testCases "relative"
	[ assert . not $ relative (fromChar8 posix "/")
	, assert . not $ relative (fromChar8 posix "/foo/bar")
	, assert $ relative (fromChar8 posix "")
	, assert $ relative (fromChar8 posix "foo/bar")
	]

testIdentity :: F.TestName -> Rules a -> Gen FilePath -> F.Test
testIdentity name r gen = testProperty name $ forAll gen $ \p -> p == decode r (encode r p)

testMixedValidityToBytes :: F.Test
testMixedValidityToBytes =
	let p = fromChar8 posix in
	let t x y = encode posix x @?= B8.pack y in
	
	testCases "mixed validity to bytes"
	[ t (p "\xB1.\xDD\xAA") "\xB1.\xDD\xAA"
	, t (p "\xB1.\xDD\xAA" </> p "foo") "\xB1.\xDD\xAA/foo"
	]

testToText :: F.Test
testToText =
	let p = fromChar8 posix in
	let t x y = toText posix x @?= emap T.pack T.pack y in
	
	testCases "toText"
	[ t (p "") (Right "")
	, t (p "ascii") (Right "ascii")
	, t (p "\xF0\x9D\x84\x9E") (Right "\x1D11E")
	, t (p "\xED\xA0\x80") (Left "\xED\xA0\x80")
	, t (p "\xF0\x9D\x84\x9E/\xED\xA0\x80") (Left "\x1D11E/\xED\xA0\x80")
	, t (p "\xED.\xF0\x9D\x84\x9E.\xA0\x80") (Left "\xED.\x1D11E.\xA0\x80")
	, t (p "\xB1.\xDD\xAA") (Left "\xB1.\x76A")
	, t (p "\xB1.\xDD\xAA" </> p "foo") (Left "\xB1.\xDD\xAA/foo")
	]

testFromText :: F.Test
testFromText =
	let t x y = fromText posix (T.pack x) @?= fromChar8 posix y in
	
	testCases "fromText"
	[ t "" ""
	, t "\x1D11E" "\xF0\x9D\x84\x9E"
	, t "\xED\xA0\x80" "\xC3\xAD\xC2\xA0\xC2\x80"
	]

testAppend :: F.Test
testAppend =
	let t x y z = toChar8 posix (append (fromChar8 posix x) (fromChar8 posix y)) @?= z in
	
	testCases "append"
	[ t "" "" ""
	, t "" "b/" "b/"
	
	-- Relative to a directory
	, t "a/" "" "a/"
	, t "a/" "b/" "a/b/"
	, t "a/" "b.txt" "a/b.txt"
	, t "a.txt" "b.txt" "a.txt/b.txt"
	, t "." "a" "./a"
	
	-- Relative to a file
	, t "a" "" "a/"
	, t "a" "b/" "a/b/"
	, t "a/b" "c" "a/b/c"
	
	-- Absolute
	, t "/a/" "" "/a/"
	, t "/a/" "b" "/a/b"
	, t "/a/" "b/" "/a/b/"
	
	-- Second parameter is absolute
	, t "/a/" "/" "/"
	, t "/a/" "/b" "/b"
	, t "/a/" "/b/" "/b/"
	]

testCommonPrefix :: F.Test
testCommonPrefix =
	let t xs y = toChar8 posix (commonPrefix (map (fromChar8 posix) xs)) @?= y in
	
	testCases "commonPrefix"
	[ t ["", ""] ""
	, t ["/", ""] ""
	, t ["/", "/"] "/"
	, t ["foo/", "/foo/"] ""
	, t ["/foo", "/foo/"] "/"
	, t ["/foo/", "/foo/"] "/foo/"
	, t ["/foo/bar/baz.txt.gz", "/foo/bar/baz.txt.gz.bar"] "/foo/bar/baz.txt.gz"
	]

testSplitExtension :: F.Test
testSplitExtension =
	let t x (y1, y2) = case splitExtension (fromChar8 posix x) of
		(base, ext) -> (toChar8 posix base, ext) @?= (y1, fmap T.pack y2) in
	
	testCases "splitExtension"
	[ t ""              ("", Nothing)
	, t "foo"           ("foo", Nothing)
	, t "foo."          ("foo", Just "")
	, t "foo.a"         ("foo", Just "a")
	, t "foo.a/"        ("foo.a/", Nothing)
	, t "foo.a/bar"     ("foo.a/bar", Nothing)
	, t "foo.a/bar.b"   ("foo.a/bar", Just "b")
	, t "foo.a/bar.b.c" ("foo.a/bar.b", Just "c")
	]

testCollapse :: F.Test
testCollapse =
	let t x y = toChar8 posix (collapse (fromChar8 posix x)) @?= y in
	
	testCases "collapse"
	[ t "./" "./"
	, t "././" "./"
	, t "../" "../"
	, t ".././" "../"
	, t "./../" "../"
	, t "parent/foo/../bar" "parent/bar"
	, t "parent/foo/.." "parent/"
	]

testParsing :: F.Test
testParsing =
	let tp x y = toChar8 posix (fromChar8 posix x) @?= y in
	let tw x y = toString windows (fromString windows x) @?= y in
	
	testCases "parsing"
	[ tp "" ""
	, tp "/" "/"
	, tp "/a" "/a"
	, tp "/a/" "/a/"
	, tp "a" "a"
	, tp "a/" "a/"
	, tp "a/b" "a/b"
	, tp "a//b" "a/b"
	, tp "a/./b" "a/./b"
	, tp "." "./"
	, tp "./" "./"
	, tp ".." "../"
	, tp "../" "../"
	
	, tw "" ""
	, tw "c:\\" "C:\\"
	, tw "c:\\a" "C:\\a"
	, tw "c:\\a\\" "C:\\a\\"
	, tw "a" "a"
	, tw "a/" "a\\"
	, tw "a\\" "a\\"
	, tw "a\\b" "a\\b"
	, tw "a\\\\b" "a\\b"
	, tw "a\\.\\b" "a\\.\\b"
	, tw "." ".\\"
	, tw ".\\" ".\\"
	, tw ".." "..\\"
	, tw "..\\" "..\\"
	]

testSplitSearchPath :: F.Test
testSplitSearchPath =
	let tp x y = map (toChar8 posix) (splitSearchPath posix (B8.pack x)) @?= y in
	let tw x y = map (toString windows) (splitSearchPath windows (T.pack x)) @?= y in
	
	testCases "splitSearchPath"
	[ tp "a:b:c" ["a", "b", "c"]
	, tp "a::b:c" ["a", "./", "b", "c"]
	, tw "a;b;c" ["a", "b", "c"]
	, tw "a;;b;c" ["a", "b", "c"]
	]

posixPaths :: Gen FilePath
posixPaths = sized $ fmap merge . genComponents where
	merge = fromChar8 posix . intercalate "/"
	validChar c = not $ elem c ['\x00', '/']
	component = do
		size <- choose (0, 10)
		vectorOf size $ arbitrary `suchThat` validChar
	genComponents n = do
		cs <- vectorOf n component
		frequency [(1, return cs), (9, return ([""] ++ cs))]

windowsPaths :: Gen FilePath
windowsPaths = sized $ \n -> genComponents n >>= merge where
	merge cs = do
		root <- genRoot
		let path = intercalate "\\" cs
		return $ fromString windows $ root ++ path
		
	reserved = ['\x00'..'\x1F'] ++ ['/', '\\', '?', '*', ':', '|', '"', '<', '>']
	validChar c = not $ elem c reserved
	component = do
		size <- choose (0, 10)
		vectorOf size $ arbitrary `suchThat` validChar
	genComponents n = do
		cs <- vectorOf n component
		frequency [(1, return cs), (9, return ([""] ++ cs))]
	
	genRoot = do
		let upperChar = elements ['A'..'Z']
		label <- frequency [(1, return Nothing), (9, fmap Just upperChar)]
		return $ case label of
			Just c -> [c, ':', '\\']
			Nothing -> "\\"

toChar8 :: Rules B.ByteString -> FilePath -> String
toChar8 r = B8.unpack . encode r

fromChar8 :: Rules B.ByteString -> String -> FilePath
fromChar8 r = decode r . B8.pack

toString :: Rules T.Text -> FilePath -> String
toString r = T.unpack . encode r

fromString :: Rules T.Text -> String -> FilePath
fromString r = decode r . T.pack

emap :: (a -> c) -> (b -> d) -> Either a b -> Either c d
emap f1 f2 = either (Left . f1) (Right . f2)