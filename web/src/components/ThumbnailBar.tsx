import { effects, thumbUrl, type EffectEntry } from "../catalog";

type Props = {
  activeId: string;
  onSelect: (id: string) => void;
};

export function ThumbnailBar({ activeId, onSelect }: Props) {
  return (
    <nav className="thumb-bar" aria-label="Effect gallery">
      {effects.map((entry) => (
        <ThumbCard
          key={entry.id}
          entry={entry}
          active={entry.id === activeId}
          onSelect={onSelect}
        />
      ))}
    </nav>
  );
}

function ThumbCard({
  entry,
  active,
  onSelect,
}: {
  entry: EffectEntry;
  active: boolean;
  onSelect: (id: string) => void;
}) {
  return (
    <button
      type="button"
      className={active ? "thumb-card is-active" : "thumb-card"}
      onClick={() => onSelect(entry.id)}
      aria-pressed={active}
    >
      <span className="thumb-frame">
        <img
          src={thumbUrl(entry)}
          alt=""
          onError={(event) => {
            event.currentTarget.style.display = "none";
          }}
        />
      </span>
      <span className="thumb-title">{entry.title}</span>
    </button>
  );
}
