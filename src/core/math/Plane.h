/*
Copyright (c) 2012 Daniele Bartolini, Simone Boscaratto

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
*/

#pragma once

#include "Types.h"
#include "Sphere.h"
#include "Vec3.h"

namespace crown
{

/// 3D Plane.
/// 
/// The form is ax + by + cz + d = 0
/// where: d = -n.Dot(p)
class Plane
{
public:

	Vec3				n;
	real				d;

public:

	/// Does nothing for efficiency.
						Plane();						
						Plane(const Plane& p);

	/// Constructs from a normal and distance factor						
						Plane(const Vec3& normal, real dist);		

	/// Normalizes the plane
	Plane&				normalize();							

	/// Returns the signed distance between point @a p and the plane
	real				distance_to_point(const Vec3& p) const;	

	/// Returns whether the plane contains the point @a p	
	bool				contains_point(const Vec3& p) const;		

	static const Plane	ZERO;
	static const Plane	XAXIS;
	static const Plane	YAXIS;
	static const Plane	ZAXIS;
};

} // namespace crown

