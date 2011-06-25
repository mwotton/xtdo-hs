module Xtdo_Test where
import Xtdo
import Test.HUnit
import Data.Time.Calendar

-- NEXT: QuickCheck + Tasks probably can do something cool

d = fromGregorian

xtdoTests =
  [ "l only shows Today" ~:
    (tasks, [Today]) ~=? (xtdo ["l"] tasks today)

  , "l a shows all tasks" ~:
    (tasks, [Today, Next, Scheduled]) ~=? (xtdo ["l", "a"] tasks today)

  , "d shows only today and next" ~:
    [Today, Next] ~=? (snd $ xtdo ["d", "mytask"] tasks today)

  , "d removes any task that matches the given name" ~:
    [chaff] ~=? (fst $ xtdo["d", "mytask"] tasks today)

  , "a adds a new unscheduled task" ~:
    [Task{name="newtask", scheduled=Nothing, category=Next}] ~=?
      (fst $ xtdo["a", "newtask"] [] today)

  , "a adds a new scheduled task for today" ~:
    [Task{name="newtask", scheduled=Just today, category=Today}] ~=?
      (fst $ xtdo["a", "0", "newtask"] [] today)

  , "a adds a new scheduled task for tomorrow" ~:
    [Task{name="newtask", scheduled=Just tomorrow, category=Scheduled}] ~=?
      (fst $ xtdo["a", "1", "newtask"] [] today)
  ]
  where tasks =
          [ Task{name="mytask", scheduled=Nothing, category=Next}
          , chaff
          ]
        chaff = Task{name="chaff",  scheduled=Nothing, category=Next}
        today = (d 2011 1 1)
        tomorrow = (d 2011 1 2)

dayTests =
  [ t "1d"  (d 2011 2 1)  (d 2011 2 2)
  , t "2d"  (d 2011 2 1)  (d 2011 2 3)
  , t "20d" (d 2011 2 1)  (d 2011 2 21)
  , t "28d" (d 2011 2 1)  (d 2011 3 1)
  , t "1w"  (d 2011 2 1)  (d 2011 2 8)
  , t "1m"  (d 2011 2 1)  (d 2011 3 1)
  , t "1y"  (d 2011 2 1)  (d 2012 2 1)
  , t "0"   (d 2011 2 1)  (d 2011 2 1)
  , t "1"   (d 2011 2 1)  (d 2011 2 2)
  , t "1m"  (d 2011 12 1) (d 2012 1 1)
  , t "1m"  (d 2011 1 31) (d 2011 2 28)
  , t "1y"  (d 2004 2 29) (d 2005 2 28)
  ]
  where t str from expected = "Xtdo.day parses " ++ str ~:
                                expected ~=? (day from str)

main = runTestTT $ TestList ( xtdoTests ++ dayTests )
