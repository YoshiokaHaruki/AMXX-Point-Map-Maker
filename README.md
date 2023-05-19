# AMXX Point Map Maker
Unified system for creating points on the map for your plugins.

This system was created in order not to produce "point generators" for certain plugins. Why do all this if you can use 1 plugin for all this?

This plugin creates points on the map and saves them in a `json` file with the name of the map. For convenience, so that the plugin can be used for many other systems at the same time, you can create points with a specific object name, so that in the future, in the desired plugin, you can search for points by this object name.

---

### Requirements

- ReHLDS, ReGameDLL, ReAPI, Metamod-R (or Metamod-P), AMX Mod X 1.9.0+

NB! In the next versions I will make Non-ReAPI support

---

### Structure of .json file

```json
{
  "object1": [
    [123, 456, 789],
    [228, 322, 1337],
    [987, 654, 321]
  ],
  "object2": [
    [1, 2, 3],
    [4, 5, 6]
  ]
}
```

- `"object1"` - this is the name of our object, followed by an array with all the points. In order to get point from the object we need, we need to use the native with the name of the object from the `json` file, which is specified in `""`
- `[*, *, *]` - One of our points

---

### Natives

```Pawn
/**
 * Writes a random point to your variable.
 * NB! There is also a check on whether the point is currently free or not.
 * 
 * @param vecOrigin			Vector variable
 * @param szObjectName			Name of the object
 * 					If you specify "all", it will take into account all objects
 * 					If object is empty/invalid = automatically sets "general"
 * @param bCheckPointIsFree		Check, point is free or not
 * 
 * @return				Returns 'true' if it got a random free point, otherwise 'false'
 */
native bool: pmm_get_random_point( const Float: vecOrigin[ 3 ], const szObjectName[ ] = "general", const bool: bCheckPointIsFree = true );

/**
 * Writes random points to your dynamic array.
 * 
 * @param arPoints			Array handle
 * @param iPointsCount			Number of points
 * @param szObjectName			Name of the object
 * 					If you specify "all", it will take into account all objects
 * 					If object is empty/invalid = automatically sets "general"
 * 
 * @return				Returns 'true' if at least 1 random point was written to the array, otherwise 'false'
 */
native bool: pmm_get_random_points( const Array: arPoints, const iPointsCount, const szObjectName[ ] = "general" );

/**
 * Writes all points to your dynamic array.
 * 
 * @param arPoints			Array handle
 * @param szObjectName			Name of the object
 * 					If you specify "all", it will take into account all objects
 * 					If object is empty/invalid = automatically sets "general"
 * 
 * @return				Returns 'true' if at least 1 point was written to the array, otherwise 'false'
 */
native bool: pmm_get_all_points( const Array: arPoints, const szObjectName[ ] = "general" );

/**
 * Destroy the main array with all points.
 * This native should be used if you have written down all the points you need somewhere in advance.
 */
native pmm_free_array( );
```
