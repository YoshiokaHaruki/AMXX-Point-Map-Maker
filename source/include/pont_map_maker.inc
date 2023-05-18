#if defined _point_map_maker_included
	#endinput
#endif
#define _point_map_maker_included

/**
 * Writes a random point to your variable.
 * NB! There is also a check on whether the point is currently free or not.
 * 
 * @param vecOrigin				Vector variable
 * @param szObjectName			Name of the object
 * 								If you specify "all", it will take into account all objects
 * 								If object is empty/invalid = automatically sets "general"
 * 
 * @return						Returns 'true' if it got a random free point, otherwise 'false'
 */
native bool: pmm_get_random_point( const Float: vecOrigin[ 3 ], const szObjectName[ ] = "general" );

/**
 * Writes random points to your dynamic array.
 * 
 * @param arPoints				Array handle
 * @param iPointsCount			Number of points
 * @param szObjectName			Name of the object
 * 								If you specify "all", it will take into account all objects
 * 								If object is empty/invalid = automatically sets "general"
 * 
 * @return						Returns 'true' if at least 1 random point was written to the array, otherwise 'false'
 */
native bool: pmm_get_random_points( const Array: arPoints, const iPointsCount, const szObjectName[ ] = "general" );

/**
 * Writes all points to your dynamic array
 * 
 * @param arPoints				Array handle
 * @param szObjectName			Name of the object
 * 								If you specify "all", it will take into account all objects
 * 								If object is empty/invalid = automatically sets "general"
 * 
 * @return						Returns 'true' if at least 1 random point was written to the array, otherwise 'false'
 */
native bool: pmm_get_all_points( const Array: arPoints, const szObjectName[ ] = "general" );