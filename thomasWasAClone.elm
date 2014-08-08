--Collisions/jumping working!
import Char
import Keyboard
import Random
import Time
import Window

--CONVENIENCE FUNCTIONS
--elem : (Eq a) => a -> [a] -> Bool
elem x xs = any (\y -> y==x) xs

listToMaybe : [a] -> Maybe a
listToMaybe x = if | x == []   -> Nothing
                   | otherwise -> Just (head x)

--INPUTS
type Input = { xDir:Int, yDir:Int, shift:Bool, key1:Bool, delta:Time }

delta = lift (\t -> t/20) (fps 60)

input = sampleOn delta (Input <~ lift .x Keyboard.arrows
                               ~ lift .y Keyboard.arrows
                               ~ Keyboard.shift
                               ~ (2 * millisecond) `Time.since` Keyboard.isDown (Char.toCode '1')
                               ~ delta)

--MODEL
type Player       = { x:Float, y:Float, vx:Float, vy:Float, w:Float, h:Float
                    , jumpingV:Float, objFill:Color, active:Bool, alive:Bool, won:Bool }
type Obstacle     = { x:Float, y:Float, w:Float, h:Float, objFill:Color }
type Game         = { characters:[Player], obstacles:[Obstacle], colliding:Obstacle, level:[Obstacle] }
type GameObject a = { a | x:Float, y:Float, w:Float, h:Float }

defaultGame : Game
defaultGame = { characters   = [player1]
              , obstacles    = [ mapSky, mapFloor
                               , { x=0, y=0, w= 300, h=50, objFill=lightGreen }
                               , { x=(-100), y=100, w=30, h=20, objFill=yellow }
                               , { x=65, y=60, w=150, h=15, objFill=purple}
                               , { x=-150, y=150, w=50, h=15, objFill=brown}
                               , { x=0, y=200, w=75, h=15, objFill=black}
                               , { x=200, y=300, w=75, h=15, objFill=darkGreen}
                               , { x=750, y=300, w=75, h=15, objFill=darkGreen}
                               , { x=1000, y=150, w=200, h=15, objFill=purple}
                               , { x=1300, y=0, w= 500, h=50, objFill=lightGreen }
                               ]
              , colliding    = death 
              , level = []
              }
mapFloor : Obstacle
mapFloor = { x=-halfWidth, y=0, w= halfWidth, h=50, objFill=lightGreen }
death    : Obstacle
death    = { x=-halfWidth, y=0, w= mainWidth, h=0, objFill=black }
mapSky   : Obstacle
mapSky   = { x=halfWidth-250, y=halfHeight, w=3*mainWidth, h=mainHeight, objFill=lightBlue }
player1  : Player
player1  =  { x=-390, y=50, vx=0, vy=0, w=10, h=50, jumpingV=8.0, objFill=red, active=True, alive=True, won=False }
player2  : Player
player2  = { x=290, y=0, vx=0, vy=0, w=25, h=25, jumpingV=5.0, objFill=blue, active=False, alive=True, won=False }

--UPDATE
collision : Player -> GameObject a -> Bool
collision p obj = (p.x >= (obj.x - obj.w/2 - p.w/2) && 
                  p.x <= (obj.x + obj.w/2 + p.w/2)) && 
                  (p.y - p.h/2 >= (obj.y + obj.h/2) && 
                  p.y  - p.h/2 <= (obj.y + obj.h/2  + p.h/2))

walkingInto p obj = (p.x <= (obj.x - obj.w/2 - p.w/2) || p.x >= (obj.x + obj.w/2 + p.w/2)) &&
                    (obj.y `elem` [p.y-p.h/2..p.y+p.h/2])

setColliding : [GameObject a] -> GameObject a -> Player -> GameObject a
setColliding os c p = 
      let collider = listToMaybe . filter (collision p) <| os
      in maybe c (\x -> x) collider

toggleActive t p = if t then { p | active <- not p.active } 
                   else p

isActive : Player -> Bool
isActive p = p.active 

dead   i p = if p.y <= 25 
             then { p | alive <- False }
             else p

clearedLevel p = if p.x >= halfWidth-50
                 then { p | won <- True }
                 else p

jump    y o p   = if p.active && y > 0 && (p.y == (o.y + o.h/2 + p.h/2 ))
                  then {p | vy <- p.jumpingV} else p

gravity t o p   = if (p.y > (o.y + o.h/2 + p.h/2))
                  then {p | vy <-  p.vy - t/4}  else p

physics t o p = {p | x <- clamp (-mainWidth) (mainWidth) <| p.x + t * p.vx * 2
                   , y <- max (p.y + t*p.vy) <| (o.y + o.h/2 + p.h/2) 
                           
                }

walk    i o p   = if p.active then {p | vx <- if | p.x <= -halfWidth && i.xDir <= 0 -> 0
                                                 | p.x >= halfWidth && i.xDir >= 0 -> 0
                                                 --| walkingInto p o -> 0
                                                 | not p.alive || p.won -> 0
                                                 | i.shift   -> toFloat i.xDir * 2
                                                 | otherwise -> toFloat i.xDir
                                 }
                  else { p | vx <- 0 }

translate i p o = if p.active  && p.x >= -halfWidth && p.x <= halfWidth
                  then { o | x <- clamp (o.x-halfWidth) (o.x+halfWidth) <| o.x - i.delta * p.vx * 2 }
                  else o

moveObjects i g = let activeP   = maybe (head g.characters) (\x -> x) <| listToMaybe . filter (\x -> isActive x) <| g.characters
                      inactiveP = filter (\x -> not . isActive <| x) <| g.characters
                  in map (translate i activeP) g.obstacles

moveInactive i g = let activeP   = maybe (head g.characters) (\x -> x) <| listToMaybe . filter (\x -> isActive x) <| g.characters
                       inactiveP = filter (\x -> not . isActive <| x) <| g.characters
                   in map (translate i activeP) inactiveP

step : Input -> Game -> [Player] 
step i g = let oColl   = setColliding g.obstacles g.colliding
           in map (\x -> clearedLevel . dead i . physics i.delta (oColl x) . walk i (oColl x) . 
                         gravity i.delta (oColl x) . jump i.yDir (oColl x) . 
                         toggleActive i.key1  <| x ) g.characters

--stepGame : Input -> Game -> Game
stepGame i g = { g | characters <- step i g
                   , obstacles  <- moveObjects i g 
               }

gameState = foldp stepGame defaultGame input

--DISPLAY
(mainHeight, mainWidth) = (700, 1000)
(halfHeight, halfWidth) = (mainHeight / 2, mainWidth /2)

make obj = 
  if obj.alive 
  then rect obj.w obj.h |> filled obj.objFill
                        |> move (obj.x, obj.y - halfHeight)
  else rect 10 50 |> filled gray
                  |> move (obj.x, obj.y - halfHeight)    

makeObstacle p obj  =[
  rect obj.w obj.h |> filled obj.objFill
                   |> move (obj.x, obj.y - halfHeight )
  --, asText (obj.x, obj.y) |> toForm
  --                        |> move (obj.x, obj.y - halfHeight )
  ]
  
display : (Int, Int) -> Game -> Element
display (w, h) g = 
    let activeP    = head g.characters 
        characters = map make <| g.characters
        obstacles  = concatMap (makeObstacle activeP) g.obstacles
    in container w h middle <| collage w h  <|
         concat [ obstacles,  (concatMap (makeObstacle activeP)  g.level),
         [ toForm [markdown|Thomas Was a Clone: Experimenting in Elm, inspired by Thomas Was Alone|] |> move (-400-activeP.x,150)
         --, toForm [markdown|&rarr;|] |> move (-750-activeP.x, -350)
         --, toForm [markdown|&uarr;|] |> move (-650-activeP.x, -300)
         --                            |> rotate (degrees -45)
         --, toForm [markdown|Press 'shift' to run!|] |> move (80-activeP.x, 40)
         , toForm (if activeP.won && activeP.alive then [markdown|Congratulations! You won!|] else spacer 1 1) |> move (0, 0)
         , toForm (if activeP.alive then spacer 1 1 else [markdown|You died!|]) |> move (0, 0) 
         --, asText (activeP.alive, activeP.x, activeP.y-activeP.h/2, round(activeP.vy)) |> toForm |> move (0, 100)
         ], characters]
      

main = lift2 display Window.dimensions gameState

