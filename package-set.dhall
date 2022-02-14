let upstream = https://github.com/dfinity/vessel-package-set/releases/download/mo-0.6.18-20220107/package-set.dhall sha256:af8b8dbe762468ce9b002fb0c62e65e1a3ee0d003e793c4404a16f8531a71b59
let Package =
    { name : Text, version : Text, repo : Text, dependencies : List Text }
let
  additions =
    [
      { name = "mutable-queue"
      , repo = "https://github.com/ninegua/mutable-queue.mo"
      , version = "2759a3b8d61acba560cb3791bc0ee730a6ea8485"
      , dependencies = [ "base" ]
      }
    ] : List Package

in upstream # additions
