# Setup

To use the test mode with mock/rover and mock/board you will need: 

- Update: ```/gameservice/src/main/webapp/META-INF/microprofile-config.properties```
	- Comment out Physical Hardware configuration
	- Uncomment Test configuration
- run ```docker-compose -f docker-compose-test.yml up --build```

To use only the mock *board* with a real rover (for example Free Roam without a game board), do not edit the properties file. Use `docker-compose.freeroam.yml` instead, which points the game service at `mockboard` through an environment variable. See [`FREE_ROAM.md`](../../FREE_ROAM.md).

# Control Scheme
```
Keyboard control scheme for mock rover: 

arrow up - Forward
arrow down - Backward
arrow left - Left
arrow right - Right

b/B - Capture blue planet
g/G - Capture green planet
p/P - Capture purple planet
y/Y - Capture yellow planet
r/R - Hit asteroid (take damage) 
```
