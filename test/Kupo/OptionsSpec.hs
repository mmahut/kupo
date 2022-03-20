-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.



-- Used to partially pattern match result of parsing default arguments. Okay-ish
-- because it's test code and, having it fail would be instantly caught.
{-# OPTIONS_GHC -fno-warn-incomplete-uni-patterns #-}

module Kupo.OptionsSpec
    ( spec
    ) where

import Kupo.Prelude

import Data.List
    ( isInfixOf )
import Kupo.App
    ( Tracers' (..) )
import Kupo.Configuration
    ( Configuration (..)
    , EpochSlots (..)
    , NetworkMagic (..)
    , NetworkParameters (..)
    , WorkDir (..)
    , mkSystemStart
    )
import Kupo.Control.MonadLog
    ( Severity (..), TracerDefinition (..), defaultTracers )
import Kupo.Data.Pattern
    ( MatchBootstrap (..), Pattern (..) )
import Kupo.Fixture
    ( somePoint )
import Kupo.Options
    ( Command (..), parseNetworkParameters, parseOptionsPure )
import Test.Hspec
    ( Expectation
    , Spec
    , context
    , expectationFailure
    , parallel
    , shouldBe
    , shouldSatisfy
    , specify
    )

spec :: Spec
spec = parallel $ do
    context "parseOptions(Pure)" $ do
        forM_ matrix $ \(args, expect) -> do
            let title = toString $ unwords $ toText <$> args
            specify title $ expect (parseOptionsPure args)

        specify "invalid" $ do
            case parseOptionsPure ["--nope"] of
                Right{} -> expectationFailure "Expected error but got success."
                Left e -> e `shouldSatisfy` isInfixOf "Invalid option"

        specify "test completion" $ do
            case parseOptionsPure ["--node-so\t"] of
                Right{} -> expectationFailure "Expected error but got success."
                Left e -> e `shouldSatisfy` isInfixOf "Invalid option"

    context "parseNetworkParameters" $ do
        specify "mainnet" $ do
            params <- parseNetworkParameters "./config/network/mainnet/cardano-node/config.json"
            networkMagic  params `shouldBe` NetworkMagic 764824073
            systemStart   params `shouldBe` mkSystemStart 1506203091
            slotsPerEpoch params `shouldBe` EpochSlots 21600

        specify "testnet" $ do
            params <- parseNetworkParameters "./config/network/testnet/cardano-node/config.json"
            networkMagic  params `shouldBe` NetworkMagic 1097911063
            systemStart   params `shouldBe` mkSystemStart 1563999616
            slotsPerEpoch params `shouldBe` EpochSlots 21600
  where
    matrix =
        [ ( []
          , shouldFail
          )
        , ( [ "--node-socket", "./node.socket" ]
          , shouldFail
          )
        , ( [ "--node-config", "./node.config" ]
          , shouldFail
          )
        , ( defaultArgs
          , shouldParseAppConfiguration $ defaultConfiguration
            { nodeSocket = "./node.socket"
            , nodeConfig = "./node.config"
            , workDir = InMemory
            }
          )
        , ( filter (/= "--in-memory") defaultArgs ++
            [ "--workdir", "./workdir"
            ]
          , shouldParseAppConfiguration $ defaultConfiguration
            { workDir = Dir "./workdir"
            }
          )
        , ( defaultArgs ++ [ "--host", "0.0.0.0" ]
          , shouldParseAppConfiguration $ defaultConfiguration
                { serverHost = "0.0.0.0" }
          )
        , ( defaultArgs ++ [ "--port", "42" ]
          , shouldParseAppConfiguration $ defaultConfiguration
            { serverPort = 42 }
          )
        , ( defaultArgs ++ [ "--port", "#" ]
          , shouldFail
          )
        , ( defaultArgs ++ [ "--since", "51292637.2e7ee124eccbc648789008f8669695486f5727cada41b2d86d1c36355c76b771" ]
          , shouldParseAppConfiguration $ defaultConfiguration
            { since = Just somePoint }
          )
        , ( defaultArgs ++ [ "--since", "#" ]
          , shouldFail
          )
        , ( defaultArgs ++ [ "--match", "*" ]
          , shouldParseAppConfiguration $ defaultConfiguration
            { patterns = [ MatchAny IncludingBootstrap ]
            }
          )
        , ( defaultArgs ++ [ "--match", "*", "--match", "*/*" ]
          , shouldParseAppConfiguration $ defaultConfiguration
            { patterns = [ MatchAny IncludingBootstrap, MatchAny OnlyShelley ]
            }
          )
        ]
        ++
        [ ( defaultArgs ++ [ "--log-level", str ]
          , shouldParseTracersConfiguration tracers
          )
        | ( str, tracers) <-
            [ ( "Debug",   defaultTracersDebug   )
            , ( "debug",   defaultTracersDebug   )
            , ( "Info",    defaultTracersInfo    )
            , ( "info",    defaultTracersInfo    )
            , ( "Notice",  defaultTracersNotice  )
            , ( "notice",  defaultTracersNotice  )
            , ( "Warning", defaultTracersWarning )
            , ( "warning", defaultTracersWarning )
            , ( "Error",   defaultTracersError   )
            , ( "error",   defaultTracersError   )
            ]
        ]
        ++
        [ ( defaultArgs ++ [ "--log-level-http-server", "Notice" ]
          , shouldParseTracersConfiguration $ defaultTracersInfo
            { tracerHttp = Const (Just Notice) }
          )
        , ( defaultArgs ++
            [ "--log-level-database", "Debug"
            , "--log-level-chain-sync", "Warning"
            ]
          , shouldParseTracersConfiguration $ defaultTracersInfo
            { tracerDatabase  = Const (Just Debug)
            , tracerChainSync = Const (Just Warning)
            }
          )
        , ( defaultArgs ++
            [ "--log-level", "Error"
            , "--log-level-configuration", "Debug"
            ]
          , shouldFail
          )
        , ( [ "version" ], flip shouldBe $ Right Version )
        , ( [ "-v" ], flip shouldBe $ Right Version )
        , ( [ "--version" ], flip shouldBe $ Right Version )
        , ( [ "--help" ]
          , flip shouldSatisfy $ isLeftWith $ \help ->
            help `deepseq` ("Usage:" `isInfixOf` help)
          )
        , ( [ "-h" ]
          , flip shouldSatisfy $ isLeftWith $ \help ->
            help `deepseq` ("Usage:" `isInfixOf` help)
          )
        ]

--
-- Helper
--

defaultConfiguration :: Configuration
defaultConfiguration = parseOptionsPure defaultArgs
    & either (error . toText) (\(Run _ cfg _) -> cfg)

defaultTracersDebug :: Tracers' IO 'MinSeverities
defaultTracersDebug = defaultTracers (Just Debug)

defaultTracersInfo :: Tracers' IO 'MinSeverities
defaultTracersInfo = defaultTracers (Just Info)

defaultTracersNotice :: Tracers' IO 'MinSeverities
defaultTracersNotice = defaultTracers (Just Notice)

defaultTracersWarning :: Tracers' IO 'MinSeverities
defaultTracersWarning = defaultTracers (Just Warning)

defaultTracersError :: Tracers' IO 'MinSeverities
defaultTracersError = defaultTracers (Just Error)

defaultArgs :: [String]
defaultArgs =
    [ "--node-socket", "./node.socket"
    , "--node-config", "./node.config"
    , "--in-memory"
    ]

shouldParseAppConfiguration
    :: Configuration
    -> (Either String (Command Proxy) -> Expectation)
shouldParseAppConfiguration cfg =
    flip shouldBe (Right (Run Proxy cfg defaultTracersInfo))

shouldParseTracersConfiguration
    :: Tracers' IO 'MinSeverities
    -> (Either String (Command Proxy) -> Expectation)
shouldParseTracersConfiguration tracers =
    flip shouldBe (Right (Run Proxy defaultConfiguration tracers))

shouldFail :: (Either String (Command Proxy)) -> Expectation
shouldFail = flip shouldSatisfy isLeft

isLeftWith :: (err -> Bool) -> Either err result -> Bool
isLeftWith predicate = \case
    Left e -> predicate e
    Right{} -> False
