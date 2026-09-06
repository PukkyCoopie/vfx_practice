import rawEffects from "../../godot/data/effects.json";

export type EffectEntry = {
  id: string;
  title: string;
  scene: string;
  thumb: string;
};

export const effects = rawEffects as EffectEntry[];

export function thumbUrl(entry: EffectEntry): string {
  return `${import.meta.env.BASE_URL}thumbs/${entry.thumb}`;
}
