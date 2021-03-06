-- FlexibleContexts needed for explicit type declarations on YAML functions
{-# LANGUAGE FlexibleContexts #-}

module Xtdo where
import System.Environment
import System.Console.ANSI

import Data.Time.Calendar
import Data.Time.Calendar.OrdinalDate
import Data.Time.Clock
import Data.List
import Data.List.Split

import Data.Object
import Data.Object.Yaml
import Control.Monad

import Control.Failure

import Text.Regex.Posix
import Text.Regex(subRegex, mkRegex)

data TaskCategory = Today | Next | Scheduled deriving(Show, Eq)
data Task = Task {
  name      :: String,
  scheduled :: Maybe Day,
  category  :: TaskCategory
} deriving(Show, Eq)
data RecurringTaskDefinition = RecurringTaskDefinition {
  -- ideally this would be 'name' but haskell doesn't like the collision with
  -- Task.name
  templateName   :: String,
  nextOccurrence :: Day,
  frequency      :: RecurFrequency
} deriving (Show, Eq)
data ProgramData = ProgramData {
  tasks     :: [Task],
  recurring :: [RecurringTaskDefinition]
} deriving (Show, Eq)
blankTask = Task{name="", scheduled=Nothing, category=Next}
data Formatter = PrettyFormatter     [TaskCategory] |
                 CompletionFormatter [TaskCategory] |
                 RecurringFormatter
                 deriving (Show, Eq)

data DayInterval     = Day | Week | Month | Year deriving (Show, Eq)
type RecurMultiplier = Int
type RecurOffset     = Int

data RecurFrequency = RecurFrequency DayInterval RecurMultiplier RecurOffset deriving (Show, Eq)

xtdo :: [String] -> ProgramData -> Day -> (ProgramData, Formatter)
xtdo ["l"]      x t = (createRecurring t x, PrettyFormatter [Today])
xtdo ["l", "a"] x t = (createRecurring t x, PrettyFormatter [Today, Next, Scheduled])
xtdo ["l", "c"] x t = (createRecurring t x, CompletionFormatter [Today, Next, Scheduled])
xtdo ["r", "l"] x _ = (x, RecurringFormatter)
xtdo ("r":"a":frequencyString:xs) x today =
  (addRecurring x makeRecurring, RecurringFormatter)
  where makeRecurring =
          RecurringTaskDefinition{
            frequency      = frequency,
            templateName   = name,
            nextOccurrence = nextOccurrence
          }
        name           = intercalate " " xs
        frequency      = parseFrequency frequencyString
        nextOccurrence = calculateNextOccurrence today frequency

xtdo ("d":xs)   x t = (createRecurring t $ replaceTasks x [task | task <- tasks x,
                           hyphenize (name task) /= hyphenize (intercalate "-" xs)
                         ],
                         PrettyFormatter [Today, Next])
xtdo ("a":when:xs) x today
  | when =~ "0d?"               = (createRecurring today $ replaceTasks x (tasks x ++
                                   [makeTask xs (Just $ day today when) Today]),
                                   PrettyFormatter [Today])
  | when =~ "([0-9]+)([dwmy]?)" = (createRecurring today $ replaceTasks x (tasks x ++
                                   [makeTask xs (Just $ day today when) Scheduled]),
                                   PrettyFormatter [Scheduled])
  | otherwise                   = (createRecurring today $ replaceTasks x (tasks x ++
                                   [makeTask ([when] ++ xs) Nothing Next]),
                                   PrettyFormatter [Next])
  where
    makeTask n s c = blankTask{name=intercalate " " n,scheduled=s,category=c}
addCategory tasks today = map (addCategoryToTask today) tasks
  where
    addCategoryToTask today task =
      task { category = if scheduled task == Just today
                          then Today
                          else Scheduled }

    addCategoryToTask today Task{name=n,scheduled=Nothing}
                 = blankTask{name=n,scheduled=Nothing,category=Next}

createRecurring :: Day -> ProgramData -> ProgramData
createRecurring today programData =
  replaceRecurring (foldl addTask programData noDuplicatedTasks) newRecurring
  where matching = filter (\x -> nextOccurrence x <= today) (recurring programData)
        newRecurring =
          map (recalculateNextOccurrence today) (recurring programData)
        recalculateNextOccurrence
          :: Day -> RecurringTaskDefinition -> RecurringTaskDefinition
        recalculateNextOccurrence today definition
          | nextOccurrence definition <= today = definition{
              nextOccurrence = calculateNextOccurrence today (frequency definition)
            }
          | otherwise                          = definition

        newtasks =
          map taskFromRecurDefintion matching
        noDuplicatedTasks =
          filter notInExisting newtasks
        notInExisting :: Task -> Bool
        notInExisting task =
          (hyphenize . name $ task) `notElem` existingTaskNames
        existingTaskNames =
          map (hyphenize . name) (tasks programData)
        taskFromRecurDefintion x =
          blankTask {name=templateName x,scheduled=Just today,category=Today}

daysOfWeek = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

parseFrequency :: String -> RecurFrequency
parseFrequency x = RecurFrequency interval multiplier (parseOffset offset)
  where matches = head $ (x =~ regex :: [[String]])
        multiplier = read (matches !! 1)
        interval   = charToInterval (matches !! 2)
        offset     = (matches !! 3)
        regex      = "([0-9]+)([dw]),?(" ++ (intercalate "|" daysOfWeek) ++ ")?"
        parseOffset :: String -> Int
        parseOffset x
          | x == ""             = 0
          | x `elem` daysOfWeek = length $ takeWhile (/= x) daysOfWeek
          | otherwise           = (read x :: Int)


        charToInterval :: String -> DayInterval
        charToInterval "d" = Day
        charToInterval "w" = Week


data StepDirection = Forward | Backward

calculateNextOccurrence :: Day -> RecurFrequency -> Day

calculateNextOccurrence today (RecurFrequency Day multiplier _) =
  (intervalToModifier Day) (toInteger multiplier) today

calculateNextOccurrence today (RecurFrequency Week multiplier offset) =
  head $ dropWhile (<= today) (frequenciesFrom startingDay)
  where frequenciesFrom day     = frequencySeq $
                                  addDays (toInteger offset) (startOfWeek day)
        frequencySeq day        = day:(frequencySeq $ stepByInterval day Forward)
        startingDay             = stepByInterval today Backward
        startOfWeek day         = fromSundayStartWeek (year day) (week day) 0
        year                    = fst . toOrdinalDate
        week                    = fst . sundayStartWeek
        stepByInterval day direction =
          (intervalToModifier Week) (toInteger multiplier * (modifier direction)) day
          where modifier Forward = 1
                modifier Backward = -1

replaceTasks :: ProgramData -> [Task] -> ProgramData
replaceTasks x tasks = ProgramData{tasks=tasks,recurring=recurring x}

replaceRecurring :: ProgramData -> [RecurringTaskDefinition] -> ProgramData
replaceRecurring x recurring = ProgramData{tasks=tasks x,recurring=recurring}

addTask :: ProgramData -> Task -> ProgramData
addTask programData task =
  ProgramData{
    tasks     = (tasks programData) ++ [task],
    recurring = (recurring programData)
  }

addRecurring :: ProgramData -> RecurringTaskDefinition -> ProgramData
addRecurring programData definition =
  ProgramData{
    tasks     = tasks programData,
    recurring = (recurring programData) ++ [definition]
  }

day :: Day -> String -> Day
day today when = modifier today
  where   matches  = head $ (when =~ "([0-9]+)([dwmy]?)" :: [[String]])
          offset   = read $ (matches !! 1)
          modifier = charToModifier (matches !! 2) offset

          -- Converts a char into a function that will transform a date
          -- by the given offset
          charToModifier :: String -> (Integer -> Day -> Day)
          charToModifier ""  = addDays
          charToModifier "d" = addDays
          charToModifier "w" = addDays . (* 7)
          charToModifier "m" = addGregorianMonthsClip
          charToModifier "y" = addGregorianYearsClip
          charToModifier other = error other

intervalToModifier :: DayInterval -> (Integer -> Day -> Day)
intervalToModifier Day = addDays
intervalToModifier Week = addDays . (* 7)

prettyFormatter :: [TaskCategory] -> ProgramData -> IO ()
prettyFormatter categoriesToDisplay programData = do
  forM categoriesToDisplay (\currentCategory -> do
    putStrLn ""

    setSGR [ SetColor Foreground Dull Yellow ]
    putStrLn $ "==== " ++ show currentCategory
    putStrLn ""

    setSGR [Reset]
    forM [t | t <- tasks programData, category t == currentCategory] (\task -> do
      putStrLn $ "  " ++ name task
      )
    )
  putStrLn ""

completionFormatter :: [TaskCategory] -> ProgramData -> IO ()
completionFormatter categoriesToDisplay programData = do
  forM (tasks programData) (putStrLn . hyphenize . name)
  putStr ""

recurringFormatter :: ProgramData -> IO ()
recurringFormatter programData = do
  putStrLn ""

  setSGR [ SetColor Foreground Dull Yellow ]
  putStrLn $ "==== Recurring"
  putStrLn ""

  setSGR [Reset]
  forM (recurring programData) 
    (putStrLn . ("  "++) .templateName)

  putStrLn ""

hyphenize x = subRegex (mkRegex "[^a-zA-Z0-9]") x "-"

finish :: (ProgramData, Formatter) -> IO ()
finish (programData, formatter) = do
  encodeFile "tasks.yml" $ Mapping
    [ ("tasks", Sequence $ map toYaml (tasks programData))
    , ("recurring", Sequence $ map recurToYaml (recurring programData))]
  doFormatting formatter programData
  where doFormatting (PrettyFormatter x)     = prettyFormatter x
        doFormatting (CompletionFormatter x) = completionFormatter x
        doFormatting (RecurringFormatter   ) = recurringFormatter
        recurToYaml x =
          Mapping [ ("templateName",   Scalar (templateName x))
                  , ("nextOccurrence", Scalar (dayToString       $ nextOccurrence x))
                  , ("frequency",      Scalar (frequencyToString $ frequency x))
                  ]
        toYaml Task{name=x, scheduled=Nothing}   =
          Mapping [("name", Scalar x)]
        toYaml Task{name=x, scheduled=Just when} =
          Mapping [("name", Scalar x), ("scheduled", Scalar $ dayToString when)]


dayToString :: Day -> String
dayToString = intercalate "-" . map show . toList . toGregorian
  where toList (a,b,c) = [a, toInteger b, toInteger c]

frequencyToString :: RecurFrequency -> String
frequencyToString x = "1d"

-- flatten = foldl (++) [] -- Surely this is in the stdlib?
flatten = concat -- it is indeed

loadYaml :: IO ProgramData
loadYaml = do
  object        <- join $ decodeFile "tasks.yml"
  mappings      <- fromMapping object
  tasksSequence <- lookupSequence "tasks" mappings
  tasks         <- mapM extractTask tasksSequence
  recurSequence <- lookupSequence "recurring" mappings
  recurring     <- mapM extractRecurring recurSequence
  return ProgramData {tasks=tasks,recurring=recurring}

extractRecurring
  :: (Failure ObjectExtractError m) =>
     StringObject -> m RecurringTaskDefinition
extractRecurring x = do
  m <- fromMapping x
  n <- lookupScalar "templateName"   m
  d <- lookupScalar "nextOccurrence" m
  f <- lookupScalar "frequency"      m
  return RecurringTaskDefinition{
      templateName   = n,
      nextOccurrence = parseDay       d,
      frequency      = parseFrequency f
    }

parseDay :: String -> Day
parseDay x = maybe (error x) id (toDay $ Just x)

extractTask
  :: (Failure ObjectExtractError m) => StringObject -> m Task
extractTask task = do
  m <- fromMapping task
  n <- lookupScalar "name" m
  let s = lookupScalar "scheduled" m :: Maybe String
  return blankTask{name=n, scheduled=toDay s, category=Next}

toDay :: Maybe String -> Maybe Day
toDay = fmap (\str -> let x = map read $ splitOn "-" str :: [Int]
                      in fromGregorian (toInteger $ x!!0) (x!!1) (x!!2))
