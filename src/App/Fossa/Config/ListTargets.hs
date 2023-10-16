{-# LANGUAGE RecordWildCards #-}

module App.Fossa.Config.ListTargets (
  mkSubCommand,
  ListTargetsCliOpts,
  ListTargetsConfig (..),
  ListTargetOutputFormat (..),
) where

import App.Fossa.Config.Analyze (
  ExperimentalAnalyzeConfig (ExperimentalAnalyzeConfig),
  GoDynamicTactic (GoModulesBasedTactic),
 )
import App.Fossa.Config.Common (
  CommonOpts (..),
  baseDirArg,
  collectBaseDir,
  commonOpts,
 )
import App.Fossa.Config.ConfigFile (
  ConfigFile (configExperimental),
  ExperimentalConfigs (gradle),
  ExperimentalGradleConfigs (gradleConfigsOnly),
  resolveLocalConfigFile,
 )
import App.Fossa.Config.EnvironmentVars (EnvVars)
import App.Fossa.Subcommand (EffStack, GetCommonOpts (getCommonOpts), GetSeverity (getSeverity), SubCommand (SubCommand))
import App.Types (BaseDir)
import Control.Effect.Diagnostics (Diagnostics)
import Control.Effect.Lift (Lift)
import Data.Aeson (ToJSON (toEncoding), defaultOptions, genericToEncoding)
import Data.Maybe (fromMaybe)
import Data.String.Conversion (toText)
import Data.Text (strip, toLower)
import Effect.Logger (Has, Logger, Severity (SevDebug, SevInfo))
import Effect.ReadFS (ReadFS)
import GHC.Generics (Generic)
import Options.Applicative (InfoMod, Parser, ReadM, eitherReader, help, long, option, optional, progDesc)

data ListTargetOutputFormat
  = Legacy
  | NdJSON
  | Text
  deriving (Eq, Ord, Show, Generic)

instance ToJSON ListTargetOutputFormat where
  toEncoding = genericToEncoding defaultOptions

parseListTargetOutput :: ReadM ListTargetOutputFormat
parseListTargetOutput = eitherReader $ \scope ->
  case toLower . strip . toText $ scope of
    "legacy" -> Right Legacy
    "ndjson" -> Right NdJSON
    "text" -> Right Text
    _ -> Left "Failed to parse format, expected one of: legacy, ndjson, or text"

mkSubCommand :: (ListTargetsConfig -> EffStack ()) -> SubCommand ListTargetsCliOpts ListTargetsConfig
mkSubCommand = SubCommand "list-targets" listTargetsInfo parser loadConfig mergeOpts

loadConfig ::
  ( Has Diagnostics sig m
  , Has (Lift IO) sig m
  , Has ReadFS sig m
  , Has Logger sig m
  ) =>
  ListTargetsCliOpts ->
  m (Maybe ConfigFile)
loadConfig = resolveLocalConfigFile . optConfig . commons

listTargetsInfo :: InfoMod a
listTargetsInfo = progDesc "List available analysis-targets in a directory (projects and sub-projects)"

parser :: Parser ListTargetsCliOpts
parser =
  ListTargetsCliOpts
    <$> commonOpts
    <*> baseDirArg
    <*> optional
      ( option
          parseListTargetOutput
          ( long "format"
              <> help "output format to use: legacy, ndjson, text (default: legacy)"
          )
      )

mergeOpts ::
  ( Has Diagnostics sig m
  , Has (Lift IO) sig m
  , Has ReadFS sig m
  ) =>
  Maybe ConfigFile ->
  EnvVars ->
  ListTargetsCliOpts ->
  m ListTargetsConfig
mergeOpts cfgfile _envvars ListTargetsCliOpts{..} = do
  let basedir = collectBaseDir cliBaseDir
      experimentalPrefs = collectExperimental cfgfile
      outputFmt = fromMaybe Legacy cliListTargetOutputFormat

  ListTargetsConfig
    <$> basedir
    <*> pure experimentalPrefs
    <*> pure outputFmt

collectExperimental :: Maybe ConfigFile -> ExperimentalAnalyzeConfig
collectExperimental maybeCfg =
  ExperimentalAnalyzeConfig
    ( fmap
        gradleConfigsOnly
        (maybeCfg >>= configExperimental >>= gradle)
    )
    GoModulesBasedTactic -- This should be ok because its discovery should not work differently than the old Go modules tactic.

data ListTargetsCliOpts = ListTargetsCliOpts
  { commons :: CommonOpts
  , cliBaseDir :: FilePath
  , cliListTargetOutputFormat :: Maybe ListTargetOutputFormat
  }

instance GetSeverity ListTargetsCliOpts where
  getSeverity ListTargetsCliOpts{commons = CommonOpts{optDebug}} = if optDebug then SevDebug else SevInfo

instance GetCommonOpts ListTargetsCliOpts where
  getCommonOpts ListTargetsCliOpts{commons} = Just commons

data ListTargetsConfig = ListTargetsConfig
  { baseDir :: BaseDir
  , experimental :: ExperimentalAnalyzeConfig
  , listTargetOutputFormat :: ListTargetOutputFormat
  }
  deriving (Show, Generic)

instance ToJSON ListTargetsConfig where
  toEncoding = genericToEncoding defaultOptions
