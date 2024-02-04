# AMXX Point Map Maker
Unified system for creating points on the map for your plugins.

This system was created in order not to produce "point generators" for certain plugins. Why do all this if you can use 1 plugin for all this?

This plugin creates points on the map and saves them in a `json` file with the name of the map. For convenience, so that the plugin can be used for many other systems at the same time, you can create points with a specific object name, so that in the future, in the desired plugin, you can search for points by this object name.

---

### Requirements

- ReHLDS, ReGameDLL, ReAPI, Metamod-R (or Metamod-P), AMX Mod X 1.9.0+

NB! In the next versions I will make Non-ReAPI support

---

### To-do List

- [x] Add `angles` to points
- [x] Add `CallBack` in native `pmm_get_random_point` for write "Custom Check of Point is Free or not"
- [ ] Remove ReAPI support

---

### Structure of .json file

```json
{
  "object1": [
    {
      "origin": [ 255, 255, 255 ],
      "angles": [ 255, 255, 255 ]
    },
    {
      "origin": [ 123, 456, 789 ],
      "angles": [ 0, 128, 0 ]
    }
  ],
  "object2": [
    {
      "origin": [ 1, 2, 3 ],
      "angles": [ 4, 5, 6 ]
    }
  ]
}
```

- `"object1"` - this is the name of our object, followed by an array with all the points. In order to get point from the object we need, we need to use the native with the name of the object from the `json` file, which is specified in `""`
- `[*, *, *]` - Array with data

---

### Natives

```Pawn
const PMM_ALL_POINTS = -1;

/**
 * Gets the number of points by the name of the object from the dynamic array.
 * 
 * @param szObjectName				Name of the object
 * 						If you specify "*" = find points from all objects
 * 						If object is invalid name (can't find) = automatically sets "general" (first from ObjectNames)
 * 
 * @return					Returns the number of points in the name of the object.
 */
native pmm_points_count( const szObjectName[ ] = "general" );

/**
 * Get a point index or an array of point indexes into a dynamic array.
 * 
 * @param szObjectName				Name of the object
 * 						If you specify "*" = find points from all objects
 * 						If object is invalid name (can't find) = automatically sets "general" (first from ObjectNames)
 * 						If object is empty = error
 * @param iPointsCount				Count of points
 * 						If PMM_ALL_POINTS (-1) = Get all points from Object
 * @param bCheckPointIsFree			Check, point is free or not
 * @param szCallBack				CallBack for bCheckPointIsFree. If this param is empty,
 * 						you specify the name of your function, in which you check whether the point is free.
 * 
 * @note Use "" to use checking from the main plugin.
 * @note Callback should be contains passing arguments as "public Point_CallBack(const Float:vecOrigin[3])"
 * @note 'return true' for stop CallBack and 'return false' for continue CallBack.
 * @note The callback will stop itself if the points have run out and will return -1.
 * 
 * @return                     			Returns integer if 'iPointsCount = 1', otherwise returns Array handle.
 * 						If any error = return -1
 */
native any: pmm_get_points( const szObjectName[ ] = "general", const iPointsCount = 1, const bool: bCheckPointIsFree = false, const szCallBack[ ] = "" );

/**
 * Gets the origin and angles of your point index
 * 
 * @param iPointIndex				Point index
 * @param vecOrigin				Array to store origin in
 * @param vecAngles				Array to store angles in
 * 
 * @return					Returns true if it was possible to get the point data, otherwise false
 */
native bool: pmm_get_point_data( const iPointIndex, const Float: vecOrigin[ 3 ], const Float: vecAngles[ 3 ] = { 0.0, 0.0, 0.0 } );

/**
 * Clears the specified object in the array
 * 
 * @param szObjectName				Name of the object
 * 						If you specify "*" = find points from all objects
 * 						If object is invalid name (can't find) = automatically sets "general"
 * 						If object is empty = error
 * 
 * @return					Returns true if cleared the array of a specific object, otherwise false
 */
native bool: pmm_clear_points( const szObjectName[ ] = "general" );
```

---

### Examples

*Get random point*
```Pawn
new iPointIndex = pmm_get_points( "general", 1 );
if ( iPointIndex == -1 )
    return;

new Float: vecOrigin[ 3 ];
pmm_get_point_data( iPointIndex, vecOrigin );
```

*Get random point, with check, point is free*
```Pawn
new iPointIndex = pmm_get_points( "general", 1, true );
if ( iPointIndex == -1 )
    return;

new Float: vecOrigin[ 3 ];
pmm_get_point_data( iPointIndex, vecOrigin );
```

*Get random point, with custom callback*
```Pawn
{
    // some code

    new iPointIndex = pmm_get_points( "general", 1, true, "Point_CallBack" );
    if ( iPointIndex == -1 )
        return;

    new Float: vecOrigin[ 3 ];
    pmm_get_point_data( iPointIndex, vecOrigin );

    // another code
}

public Point_CallBack( const Float: vecOrigin[ 3 ] )
{
    if ( vecOrigin[ 2 ] >= 128.0 )
    {
        // Point is fit
        return true;
    }

    // The point does not fit - we take the next one
    return false;
}
```

*Get N random points from object*
```Pawn
new Array: arPoints = pmm_get_points( "market_place", 5 );
if ( arPoints != Invalid_Array )
{
    /**
     * In arPoints, we got 5 random points from the "market_place" object
     * Next, we already make our own code
     */

    // Do not forget to destroy your array with points
    ArrayDestroy( arPoints );
}
```

*Get ALL points from ALL objects*
```Pawn
new Array: arPoints = pmm_get_points( "*", PMM_ALL_POINTS );
if ( arPoints != Invalid_Array )
{
    /**
     * In arPoints we got absolutely all points from all objects
     * Next, we already make our own code
     */

    // Do not forget to destroy your array with points
    ArrayDestroy( arPoints );
}
```

*Get ALL points from object and then clearing the main array of points from the object we need*
```Pawn
new Array: arPoints = pmm_get_points( "presents", PMM_ALL_POINTS );
if ( arPoints != Invalid_Array )
{
    /**
     * In arPoints we got absolutely all points from the "presents" object
     * Next, we already make our own code
     */

    // Do not forget to destroy your array with points
    ArrayDestroy( arPoints );
}

// Clearing the main array from the points of the "presents" object
pmm_clear_points( "presents" );
```

*Get the number of ALL available points*
```Pawn
{
	// some code

	new iPointsCount = pmm_points_count( "*" );

	// some code
}
```

*Get the number of points in an object*
```Pawn
{
	// some code

	new iPointsCount = pmm_points_count( "presents" );

	// some code
}
```
