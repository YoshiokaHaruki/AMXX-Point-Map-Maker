#if defined _point_map_maker_included
	#endinput
#endif
#define _point_map_maker_included

const PMM_ALL_POINTS = -1;

/**
 * Gets the number of points by the name of the object from the dynamic array.
 * 
 * @param szObjectName				Name of the object
 * 									If you specify "*" = find points from all objects
 * 									If object is invalid name (can't find) = automatically sets "general" (first from ObjectNames)
 * 
 * @return							Returns the number of points in the name of the object.
 */
native pmm_points_count( const szObjectName[ ] = "general" );

/**
 * Get a point index or an array of point indexes into a dynamic array.
 * 
 * @param szObjectName				Name of the object
 * 									If you specify "*" = find points from all objects
 * 									If object is invalid name (can't find) = automatically sets "general" (first from ObjectNames)
 * 									If object is empty = error
 * @param iPointsCount				Count of points
 * 									If PMM_ALL_POINTS (-1) = Get all points from Object
 * @param bCheckPointIsFree			Check, point is free or not
 * @param szCallBack				CallBack for bCheckPointIsFree. If this param is empty,
 * 									you specify the name of your function, in which you check whether the point is free.
 * 
 * @note Use "" to use checking from the main plugin.
 * @note Callback should be contains passing arguments as "public Point_CallBack(const Float:vecOrigin[3])"
 * @note 'return true' for stop CallBack and 'return false' for continue CallBack.
 * @note The callback will stop itself if the points have run out and will return -1.
 * 
 * @return                  		Returns integer if 'iPointsCount = 1', otherwise returns Array handle.
 * 									If any error = return -1
 */
native any: pmm_get_points( const szObjectName[ ] = "general", const iPointsCount = 1, const bool: bCheckPointIsFree = false, const szCallBack[ ] = "" );

/**
 * Gets the origin and angles of your point index
 * 
 * @param iPointIndex				Point index
 * @param vecOrigin					Array to store origin in
 * @param vecAngles					Array to store angles in
 * 
 * @return							Returns true if it was possible to get the point data, otherwise false
 */
native bool: pmm_get_point_data( const iPointIndex, const Float: vecOrigin[ 3 ], const Float: vecAngles[ 3 ] = NULL_VECTOR );

/**
 * Clears the specified object in the array
 * 
 * @param szObjectName				Name of the object
 * 									If you specify "*" = find points from all objects
 * 									If object is invalid name (can't find) = automatically sets "general"
 * 									If object is empty = error
 * 
 * @return							Returns true if cleared the array of a specific object, otherwise false
 */
native bool: pmm_clear_points( const szObjectName[ ] = "general" );