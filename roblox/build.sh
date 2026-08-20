#!/bin/bash
# Sestavi DoggioWarsPrototype.rbxlx z lua zdrojaku v teto slozce.
# Zdrojem pravdy jsou .lua soubory -- po uprave spust ./build.sh znovu.
set -e
cd "$(dirname "$0")"
OUT=DoggioWarsPrototype.rbxlx

{
cat <<'XML'
<roblox xmlns:xmime="http://schemas.microsoft.com/2003/10/Serialization/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
	<Item class="Workspace" referent="RBXWS">
		<Properties>
			<string name="Name">Workspace</string>
		</Properties>
		<Item class="SpawnLocation" referent="RBXSPAWN">
			<Properties>
				<string name="Name">SpawnLocation</string>
				<bool name="Anchored">true</bool>
				<bool name="CanCollide">false</bool>
				<float name="Transparency">1</float>
				<int name="Duration">0</int>
				<CoordinateFrame name="CFrame">
					<X>0</X><Y>1400</Y><Z>0</Z>
					<R00>1</R00><R01>0</R01><R02>0</R02>
					<R10>0</R10><R11>1</R11><R12>0</R12>
					<R20>0</R20><R21>0</R21><R22>1</R22>
				</CoordinateFrame>
				<Vector3 name="size"><X>12</X><Y>1</Y><Z>12</Z></Vector3>
			</Properties>
		</Item>
	</Item>
	<Item class="ServerScriptService" referent="RBXSSS">
		<Properties>
			<string name="Name">ServerScriptService</string>
		</Properties>
		<Item class="Script" referent="RBXSRV">
			<Properties>
				<string name="Name">IslandGenerator</string>
				<ProtectedString name="Source"><![CDATA[
XML
cat island-generator.server.lua
cat <<'XML'
]]></ProtectedString>
			</Properties>
		</Item>
	</Item>
	<Item class="StarterPlayer" referent="RBXSP">
		<Properties>
			<string name="Name">StarterPlayer</string>
		</Properties>
		<Item class="StarterPlayerScripts" referent="RBXSPS">
			<Properties>
				<string name="Name">StarterPlayerScripts</string>
			</Properties>
			<Item class="LocalScript" referent="RBXCLI">
				<Properties>
					<string name="Name">FlightController</string>
					<ProtectedString name="Source"><![CDATA[
XML
cat flight-controller.client.lua
cat <<'XML'
]]></ProtectedString>
				</Properties>
			</Item>
		</Item>
	</Item>
</roblox>
XML
} > "$OUT"

xmllint --noout "$OUT" && echo "OK: $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
